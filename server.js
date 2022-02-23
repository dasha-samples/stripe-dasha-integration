require("dotenv").config({ path: ".env" });
const express = require("express");
const _ = require("lodash");
const axios = require("axios");
const http = require("http");
const { Stripe } = require("stripe");
// const stripe = require("stripe")

const PORT = process.env.PORT ?? "8080";
let stripe;
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const STRIPE_PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY;

const transaction_storage = {};
function save_payment_intent(conversation_id, payment_intent_id) {
  if (transaction_storage[conversation_id] === undefined)
    transaction_storage[conversation_id] = {};
  transaction_storage[conversation_id]["payment_intent_cs"] = payment_intent_id;
}
function get_payment_intent(conversation_id) {
  if (transaction_storage[conversation_id] === undefined)
    throw new Error(`Conversation ${conversation_id} not found`);
  return transaction_storage[conversation_id]["payment_intent_cs"];
}
function delete_conversation_info(conversation_id) {
  delete transaction_storage[conversation_id];
}

function checkEnvironment(req, res, next) {
  if (_.isNil(STRIPE_SECRET_KEY))
    throw new Error("Variable STRIPE_SECRET_KEY is not set in the environment");
  if (_.isNil(STRIPE_PUBLISHABLE_KEY))
    throw new Error(
      "Variable STRIPE_PUBLISHABLE_KEY is not set in the environment"
    );
  stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  next();
}

function createApp() {
  const app = express();
  app.use(
    express.json({ type: ["application/json", "application/json-patch+json"] })
  );

  app.use(checkEnvironment);

  app.get("/health", (req, res) => {
    console.log("got request healthcheck");
    return res.status(200).send("OK");
  });

  app.post("/api/shipping_info", (req, res) => {
    console.log(req.body);
    const { address_data } = req.body;
    console.log(
      `Getting shipping info for address ${JSON.stringify(address_data)}...`
    );

    // mocked getting information about the shipping time and cost
    // use stripe api or implement your own logic

    const price = 1000; // delivery price amount in cents
    const time_days = 2; // delivery time in days
    const taxes = 100; // taxes amount in cents
    const shipping_info = { price, time_days, taxes };
    console.log(`Found shipping info ${JSON.stringify(shipping_info)}`);
    res.json(shipping_info);
    res.end();
  });

  app.get("/api/product_info/:product_id", async (req, res) => {
    const product_id = req.params.product_id;

    try {
      console.log(`Searching information about the product ${product_id}...`);
      const products = await stripe.products.list({
        ids: [product_id],
      });
      if (products.data.length == 0)
        return res.status(404).send(`Product '${product_id}' not found`);

      const description = products.data[0].description;

      const prices = await stripe.prices.list({
        product: product_id,
      });
      if (products.data.length == 0)
        return res
          .status(404)
          .send(`Prices for product '${product_id}' not found`);

      const price = prices.data[0].unit_amount;

      const product_info = {
        product_id,
        description,
        price,
      };
      console.log(`Found product info ${JSON.stringify(product_info)}`);
      return res.json(product_info);
    } catch (e) {
      console.log(`Error: ${e.message}`);
      return res.status(400).send({ message: e.message });
    }
  });

  app.get("/api/stripe_publishable_key", (req, res) => {
    console.log(`Returning publishable key...`);
    res.json({ key: STRIPE_PUBLISHABLE_KEY });
  });

  app.post("/api/init_payment/:conversation_id", async (req, res) => {
    const conversation_id = req.params.conversation_id;
    console.log(
      `Initiating payment intent for conversation ${conversation_id}...`
    );
    const { amount } = req.body;
    try {
      const payment_intent = await stripe.paymentIntents.create({
        amount,
        currency: "usd",
        payment_method_types: ["card"], // allow card only
      });
      save_payment_intent(conversation_id, payment_intent.id);
      console.log(`Created payment intent ${payment_intent.id}`);
      return res.json({ payment_intent_id: payment_intent.id });
    } catch (e) {
      console.log(`Error: ${e.message}`);
      return res.status(400).json({ statusCode: 400, message: e.message });
    }
  });

  app.post("/api/confirm_payment/:conversation_id", async (req, res) => {
    const conversation_id = req.params.conversation_id;
    console.log(`Confirming payment for conversation ${conversation_id}...`);
    const { card } = req.body;
    try {
      const payment_intent_id = get_payment_intent(conversation_id);
      console.log(`Loaded client secret`);
      const paymentMethod = await stripe.paymentMethods.create({
        type: "card",
        card: card,
      });
      console.log(`Created payment method ${paymentMethod.id}`);

      const paymentIntent = await stripe.paymentIntents.confirm(
        payment_intent_id,
        { payment_method: paymentMethod.id }
      );
      const success =
        paymentIntent.charges.data.slice(-1)[0].status === "succeeded";

      console.log(`Confirmation finished, success: ${success}.`);
      if (success) console.log("Payment accepted");
      return res.json({ success: success });
    } catch (e) {
      console.log(`Error: ${e.message}`);
      return res.status(400).json({ statusCode: 400, message: e.message });
    }
  });
  app.post("api/finalize_conversation/:conversation_id", async (req, res) => {
    const conversation_id = req.params.conversation_id;
    console.log(`Finalizing conversation ${conversation_id}...`);
    const payment_id = get_payment_intent(conversation_id);
    if (payment_id) {
      const existing_payment = await stripe.paymentIntents.retrieve(payment_id);
      if (existing_payment.charges.data.slice(-1)[0].status !== "succeeded") {
        console.log(`Cancelling payment ${conversation_id}...`);
        await stripe.paymentIntents.cancel(payment_id);
      }
      delete_conversation_info(conversation_id);
    }

    res.sendStatus(200);
  });
  return app;
}

async function main() {
  const app = createApp();
  const httpServer = http.createServer(app);
  httpServer
    .listen(PORT)
    .on("listening", () => {
      console.log(`Web server listening on localhost:${PORT}`);
    })
    .on("error", (err) => {
      console.log(`Failed to open port ${PORT}: ${err}`);
      process.exit(1);
    });
}

main();
