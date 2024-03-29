const dasha = require("@dasha.ai/sdk");
const axios = require("axios");
require("dotenv").config({ path: ".env" });
const { v4: uuidv4 } = require("uuid");
const moment = require("moment");

const SERVER_PORT = process.env.PORT ?? "8080";
const SERVER_URL = `http://localhost:${SERVER_PORT}`;
const CONVERSATION_ID = uuidv4();

async function main() {
  try {
    const server_is_ok =
      (await axios.get(`${SERVER_URL}/health`)).status == 200;
    if (!server_is_ok) throw new Error(`Server ${SERVER_URL} is not healthy`);
  } catch (e) {
    throw new Error(`Server ${SERVER_URL} is not responding: ${e.message}`);
  }

  const endpoint = process.argv[3];
  console.log({ endpoint });
  if (endpoint === undefined)
    throw new Error("Please, provide phone to call or 'chat'");

  const app = await dasha.deploy("./app");
  await app.start({ concurrency: 10 });

  // set external functions
  for (const [func_name, func] of Object.entries(app_external_functions)) {
    app.setExternal(func_name, func);
  }

  const input = { phone: endpoint };
  const conversation = app.createConversation(input);

  const channel = endpoint !== "chat" ? "audio" : "text";
  if (channel === "audio") {
    conversation.on("transcription", (log) => console.log(log));
  }

  if (channel === "text") {
    await dasha.chat.createConsoleChat(conversation);
  }

  conversation.audio.tts = "dasha";
  conversation.audio.stt = "default";
  conversation.audio.noiseVolume = 0;
  try {
    const result = await conversation.execute({ channel });
    console.log(result.output);
  } catch (e) {
    console.log(
      `During the conversation the error occured: ${JSON.stringify(e.message)}`
    );
  } finally {
    await axios.post(
      `${SERVER_URL}/api/finalize_conversation/${CONVERSATION_ID}`,
      {}
    );
    await app.stop();
    app.dispose();
  }
}

function get_address_name(address_data) {
  return [
    address_data.housenumber,
    address_data.streetname,
    address_data.streetd,
  ].join(" ");
}

function join_numberwords(numberwords) {
  return numberwords.map((nw) => nw.value).join("");
}

const app_external_functions = {
  get_product: async (argv, conv) => {
    const product_id = join_numberwords(argv.numberwords);
    let ret;
    await axios
      .get(`${SERVER_URL}/api/product_info/${product_id}`)
      .then((res) => {
        ret = res.data;
      })
      .catch((e) => {
        console.log(`Could not get product '${product_id}': ${e.message}`);
        ret = null;
      });
    return ret;
  },
  get_shipping_info: async (argv, conv) => {
    const address_data = argv.address_data;
    /* go to mock server and return mock value */
    let ret;
    await axios
      .post(`${SERVER_URL}/api/shipping_info`, {
        address_data,
      })
      .then((response) => {
        const shipping_info = response.data;
        /* process address_data to obtain human readable address */
        const address_name = get_address_name(address_data);
        /* calculate delivery date using current moment and shipping_time */
        const delivery_moment = moment().add(shipping_info.time_days, "days");
        const delivery_date = {
          month: delivery_moment.format("MMMM"),
          date: delivery_moment.format("DD"),
          day_of_week: delivery_moment.format("dddd"),
        };
        ret = { ...shipping_info, address_name, delivery_date };
      })
      .catch((e) => {
        ret = null;
      });
    return ret;
  },

  init_payment: async (argv, conv) => {
    const amount = argv.amount;
    let ret;
    await axios
      .post(`${SERVER_URL}/api/init_payment/${CONVERSATION_ID}`, {
        amount,
      })
      .then((res) => {
        ret = true;
      })
      .catch((error) => {
        ret = false;
      });
    return ret;
  },

  parse_card_number: (argv, conv) => {
    let card_number = join_numberwords(argv.numberwords);
    if (card_number.length == 16) return card_number;
    const num_re = /\d+/g;
    card_number = argv.raw.match(num_re).join("");
    return card_number.length == 16 ? card_number : null;
  },
  parse_exp_date: (argv, conv) => {
    const exp_date_m = moment(new Date(argv.user_input));
    if (!exp_date_m.isValid()) return null;
    const exp_date = {
      exp_month_str: exp_date_m.format("MMMM"),
      exp_month: exp_date_m.month() + 1,
      exp_year: exp_date_m.year(),
    };
    return exp_date;
  },
  parse_cvc_code: (argv, conv) => {
    let cvc = join_numberwords(argv.numberwords);
    if (cvc.length == 3) return cvc;
    const num_re = /\d+/g;
    cvc = argv.raw.match(num_re).join("");
    return cvc.length == 3 ? cvc : null;
  },
  confirm_payment: async (argv, conv) => {
    let ret;
    const number = argv.card_number;
    const { exp_month, exp_year } = argv.card_exp_date;
    const cvc = argv.card_cvc_code;
    const card = { number, exp_month, exp_year, cvc };
    console.log("payment card object", card);
    await axios
      .post(
        `${SERVER_URL}/api/confirm_payment/${CONVERSATION_ID}`,
        {
          card,
        }
      )
      .then((res) => {
        ret = res.data.success;
      })
      .catch((error) => {
        ret = false;
      });
    return ret;
  },
  throw_error: (argv, conv) => {
    throw new Error(argv.msg);
  },
};

main().catch((e) => {
  console.log(e);
});
