require("dotenv").config({ path: ".env" });

const sk = process.env.STRIPE_SECRET_KEY;
console.log(sk);

const { Stripe } = require("stripe");
const stripe = new Stripe(sk);

const product_1 = {
  id: "123",
  name: "test-jacket",
  description: "Winter Blues jacket in white",
};
const product_2 = {
  id: "456",
  name: "test-headphones",
  description: "Apple AirPods 3",
};
const product_3 = {
  id: "789",
  name: "test-coffee-mug",
  description: "Ounce Coffee Mug",
};

const price_1 = {
  product: "123",
  currency: "usd",
  unit_amount: 12550,
};
const price_2 = {
  product: "456",
  currency: "usd",
  unit_amount: 17975,
};
const price_3 = {
  product: "789",
  currency: "usd",
  unit_amount: 2050,
};


async function main() {
  const products = [product_1, product_2, product_3];
  const prices = [price_1, price_2, price_3];
  for (const i in products) {
    // create product
    const product = products[i];
    stripe.products.create(product);
    // create price
    const price = prices[i];
    stripe.prices.create(price);
  }
}

main().catch((e) => {
  console.log(`Error: ${e.message}`);
});
