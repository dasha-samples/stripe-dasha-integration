# Installation

1. `npm i` to install dependencies
2. Create `stripe` account (or sign in)
3. Create `.env` file with stripe credentials to set env variables `STRIPE_PUBLISHABLE_KEY` and `STRIPE_SECRET_KEY` (see `.env.example`)
4. Create products in your `stripe` account. Note that product ids are expected to be numbers
   - You may create them manually using stripe dashaboard
   - Also you may launche script `create-or-update-test-products.js` via running command `node create-or-update-test-products.js`

# Running

1. `node server.js` to run mock server (the default port is `8080`, you can configure it in `.env` file using variable `PORT`)
2. `npm start chat` to run application as chat or `npm start <your_phone_number>` to run voice call
