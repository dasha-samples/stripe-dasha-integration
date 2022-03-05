import "commonReactions/all.dsl";
import "types.dsl";

context
{
    // declare input variables here
    input phone: string;

    // number of attempts to ask each question again
    num_attempts: number = 2;

    card_number: string?;
    card_exp_date: ExpDate?;
    card_cvc_code: string?;
    
    output chosen_product_info: ProductInfo?;
    output shipping_info: ShippingInfo?;
    output payment_success: boolean = false;
    output total_cost: number = 0; 
}

// declare external functions here
external function get_product(numberwords: unknown[]): ProductInfo;
external function get_shipping_info(address_data: unknown): ShippingInfo;
external function init_payment(amount: number): boolean;
external function parse_card_number(numberwords: unknown[], raw: string): string;
external function parse_exp_date(user_input: string): ExpDate;
external function parse_cvc_code(numberwords: unknown[], raw: string): string;
external function confirm_payment(card_number: string?,card_exp_date: ExpDate?,card_cvc_code: string?): boolean;

external function throw_error(msg: string): empty;

start node root
{
    do //actions executed in this node
    {
        // disable this digression until collecting information is complete
        digression disable { order_delivery };
        #connectSafe($phone); // connecting to the phone number which is specified in index.js that it can also be in-terminal text chat
        #waitForSpeech(1000); // give the person a second to start speaking
        #sayText("Hi there. Dasha on the line, how may I help you today?");
        wait *; // wait for a response
    }
}

digression payment_phone
{
    conditions
    {
        on #messageHasIntent("payment_phone");
        // TODO remove this mock
        on true && #getVisitCount("payment_phone") == 0;
    }
    do
    {
        #sayText("Yeah, sure thing I'd be glad to help.");
        #sayText("Could you tell me the item number please?");
        wait*;
    }
    transitions
    {
        product_number: goto validate_product_number on #messageHasData("numberword");
    }
}

node validate_product_number
{
    do
    {
        #sayText("Alright, let me check.");
        set $chosen_product_info = external get_product(#messageGetData("numberword"));
        #log($chosen_product_info);
        if ($chosen_product_info is null)
        {
            #sayText("I'm sorry, I could not find this item number.");
            if (#getVisitCount("validate_product_number") >= $num_attempts + 1)
                goto force_sorry_bye;
            #sayText("Could you say it one more time, please?");
        }
        else
        {
            var dollars = ($chosen_product_info.price / 100).trunc().toString();
            var cents = ($chosen_product_info.price % 100).toString();
            #sayText("So, the " + $chosen_product_info.description + " for " + dollars + " dollars and " + cents + " cents. Is that right?");
        }
        wait*;
    }
    transitions
    {
        ask_address: goto ask_address on #messageHasIntent("yes") priority 1;
        repeat_item_number: goto validate_product_number on $chosen_product_info is null 
                                                            and #messageHasData("numberword") 
                                                            and #getVisitCount("validate_product_number") < $num_attempts priority 1;
        
        no: goto invalid_product on #messageHasIntent("no") and #getVisitCount("validate_product_number") < $num_attempts;
        sorry_bye: goto sorry_bye on #messageHasIntent("no") and #getVisitCount("validate_product_number") >= $num_attempts;
        force_sorry_bye: goto sorry_bye;
    }
}

node ask_address
{
    do
    {
        #sayText("Uh-huh. Okay. Let me just calculate the total order amount with taxes and shipping costs.");
        #sayText("I would need to know your address for the shipping. Could you tell me your address, please?");
        wait*;
    }
    transitions
    {
        validate_address: goto validate_address on #messageHasData("address");
    }
}

node validate_address
{
    do
    {
        var address_data = #messageGetData("address")[0];
        #log(address_data);
        set $shipping_info = external get_shipping_info(address_data);
        #log($shipping_info);
        if ($shipping_info is null)
        {
            external throw_error("Unexpected error: shipping_info is null");
        }
        else
        {
            #sayText($shipping_info.address_name + ". Is that correct?");
        }
        wait*;
    }
    transitions
    {
        validate_price: goto validate_price on #messageHasIntent("yes");
        invalid_address: goto invalid_address on #messageHasIntent("no") and #getVisitCount("validate_address") < $num_attempts;
        sorry_bye: goto sorry_bye on #messageHasIntent("no") and #getVisitCount("validate_address") >= $num_attempts;
    }
}

node validate_price 
{
    do
    {
        if ($shipping_info is null)
        {
            external throw_error("Unexpected error: shipping_info is null");
        }
        else if ($chosen_product_info is null)
        {
            external throw_error("Unexpected error: chosen_product_info is null");
        }
        else 
        {
            #sayText("Got it.");
            var dollars = ($shipping_info.price / 100).trunc().toString();
            var cents = ($shipping_info.price % 100).toString();
            #sayText("So, the shipping costs " + dollars + " dollars and " + cents + " cents.");
            set dollars = ($shipping_info.taxes / 100).trunc().toString();
            set cents = ($shipping_info.taxes % 100).toString();
            #sayText("The taxes are " + dollars + " dollars and " + cents + " cents.");
            
            set $total_cost = $chosen_product_info.price + $shipping_info.price + $shipping_info.taxes;
            set dollars = ($total_cost / 100).trunc().toString();
            set cents = ($total_cost % 100).toString();
            //one moment... 
            #sayText("And... The total cost would be " + dollars + " dollars and " + cents + " cents.");
            #sayText("Would you like to proceed with your purchase?");
        }
        wait *;
    }
    transitions
    {
        init_payment: goto init_payment on #messageHasIntent("yes");
        decline_payment: goto decline_payment on #messageHasIntent("no");
    }
}

node init_payment
{
    do
    {
        var success = external init_payment($total_cost);
        if (success) {
            goto ask_card_number;
        } 
        else {
            #sayText("Something went wrong. Probably, some problems on our server.");
            #sayText("Sorry for the technical issues. Have a nice day!");
            exit;
        }
        
    }
    transitions
    {
        ask_card_number: goto ask_card_number;
    }
}

node ask_card_number
{
    do
    {
        #setVadPauseLength(2);
        if (#getVisitCount("ask_card_number") == 1)
            #sayText("Ok. Now, let's get your card details. Could you tell me your card number please?");
        wait*;
    }
    transitions
    {
        validate_card_number: goto validate_card_number on true;
    }
}

node validate_card_number
{
    do
    {
        set $card_number = external parse_card_number(#messageGetData("numberword"), #getMessageText());
        #log($card_number);
        if ($card_number is null)
        {
            #sayText("I'm sorry, I didn't quite catch that. Could you say it again?");
            goto ask_again;
        }
        else
        {
            #sayText($card_number.slice(0,4).split("").join(" ") + ", " + 
                    $card_number.slice(4,8).split("").join(" ") + ", " + 
                    $card_number.slice(8,12).split("").join(" ") + ", " + 
                    $card_number.slice(12,16).split("").join(" "));
            #sayText("Is that correct?");
        }
        wait*;
    }
    transitions
    {
        ask_again: goto ask_card_number;
        ask_exp_date: goto ask_exp_date on #messageHasIntent("yes");
        invalid_card_number: goto invalid_card_number on #messageHasIntent("no") and #getVisitCount("validate_card_number") < $num_attempts;
        sorry_bye: goto sorry_bye on #messageHasIntent("no") and #getVisitCount("validate_card_number") >= $num_attempts;
    }
}

node ask_exp_date
{
    do
    {
        if (#getVisitCount("ask_exp_date") == 1)
            #sayText("Okay, thank you. Now, could you tell me the expiration date?");
        wait*;
    }
    transitions
    {
        validate_exp_date: goto validate_exp_date on #messageHasData("date_time", { month: true }) 
            and 
            (#messageHasData("numberword") or #messageHasData("date_time", { year: true }));
    }
}

node validate_exp_date
{
    do
    {
        set $card_exp_date = external parse_exp_date(#getMessageText());
        #log($card_exp_date);
        if ($card_exp_date is null)
        {
            #sayText("I'm sorry, I didn't quite catch that. Could you say it again?");
            goto ask_again;
        }
        else {
            #sayText($card_exp_date.exp_month_str + " " + $card_exp_date.exp_year.toString());
            #sayText("Am I right?");
        }
        wait*;
    }
    transitions
    {
        ask_again: goto ask_exp_date;
        ask_cvc_code: goto ask_cvc_code on #messageHasIntent("yes");
        invalid_exp_date: goto invalid_exp_date on #messageHasIntent("no")  and #getVisitCount("validate_exp_date") < $num_attempts;
        sorry_bye: goto sorry_bye on #messageHasIntent("no") and #getVisitCount("validate_exp_date") >= $num_attempts;
    }
}

node ask_cvc_code
{
    do
    {
        if (#getVisitCount("ask_cvc_code") == 1)
            #sayText("Great, got it. And the three digit code on the back of the card?");
        wait*;
    }
    transitions
    {
        validate_cvc_code: goto validate_cvc_code on #messageHasData("numberword");
    }
}

node validate_cvc_code
{
    do
    {
        var parsed_cvc = external parse_cvc_code(#messageGetData("numberword"), #getMessageText());
        set $card_cvc_code = parsed_cvc;
        #log($card_cvc_code);
        if (parsed_cvc is null)
        {
            #sayText("I'm sorry, I didn't quite catch that. Could you say it again?");
            goto ask_again;
        }
        #sayText("Thanks for that.");
        goto ask_charge;
    }
    transitions
    {
        ask_again: goto ask_cvc_code;
        ask_charge: goto ask_charge;
    }
}

node ask_charge
{
    do
    {
        var dollars = (($total_cost / 100).trunc()).toString();
        var cents = ($total_cost % 100).toString();
        #sayText("Great, I have your credit card details. The order total is " + dollars + " dollars and " + cents + " cents");
        #sayText("Are you ready for me to charge your card and complete the order?");
        wait*;
    }
    transitions
    {
        yes: goto charge on #messageHasIntent("yes");
        no: goto decline_payment on #messageHasIntent("no");
    }
}

node charge
{
    do
    {
        #sayText("Give me one second...");
        set $payment_success = external confirm_payment($card_number, $card_exp_date, $card_cvc_code);
        if (!$payment_success)
        {
            set $chosen_product_info = null;
            set $shipping_info = null;
            #sayText("I am sorry, something went wrong during the transaction. Your card is not accepted.");
            exit;
        }
        goto any_qs;
    }
    transitions
    {
        any_qs: goto any_qs;
    }
}

node any_qs
{
    do
    {
        digression enable { order_delivery };
        #sayText("Alright, the payment just went through. Do you have any questions for me at this time?");
        wait*;
    }
    transitions
    {
        no_qs: goto bye on #messageHasIntent("no");
    }
}

digression order_delivery
{
    conditions
    {
        on #messageHasIntent("order_delivery");
    }
    do
    {
        if ($shipping_info is null)
        {
            external throw_error("Unexpected error: shipping_info is null");
        }
        else
        {
            var delivery_time_days = $shipping_info.time_days.toString();
            var delivery_day_of_week = $shipping_info.delivery_date.day_of_week;
            #sayText("Oh that's right. Your jacket should arrive in approximately " + delivery_time_days + " days, so that'd be " + delivery_day_of_week);
        }
        wait*;
    }
    transitions
    {
        bye: goto bye on true;
    }
}

node bye
{
    do
    {
        #sayText("It was my pleasure to help. Have a fantastic day! Bye!");
        exit;
    }
}

node decline_payment
{
    do
    {
        set $chosen_product_info = null;
        set $shipping_info = null;
        #sayText("Ok, I've got you.");
        #sayText("Thank you for your call. Call me if you change your mind.");
        #sayText("Have a fantastic day! Bye!");
        exit;
    }
}

node sorry_bye
{
    do
    {
        set $chosen_product_info = null;
        set $shipping_info = null;
        #sayText("I'm sorry I can barely hear you. I'll try to call you later! Bye!");
        exit;
    }
}

node invalid_product
{
    do
    {
        #sayText("Ok, maybe I've got you wrong. Please, tell me the item number?");
        wait*;
    }
    transitions
    {
        repeat_product_number: goto validate_product_number on #messageHasData("numberword");
    }
}

node invalid_address
{
    do
    {
        #sayText("I'm sorry, maybe I've got you wrong. Please, tell me your address again?");
        wait*;
    }
    transitions
    {
        repeat_address: goto validate_address on #messageHasData("address");
    }
}

node invalid_card_number
{
    do
    {
        #sayText("I'm sorry, maybe I've got you wrong. Please, tell me your card number again?");
        wait*;
    }
    transitions
    {
        repeat_address: goto validate_card_number on #messageHasData("numberword");
    }
}

node invalid_exp_date
{
    do
    {
        #sayText("I'm sorry, maybe I've got you wrong. Please, tell me your card number again?");
        wait*;
    }
    transitions
    {
        repeat_address: goto validate_exp_date on #messageHasData("date_time", { month: true }) 
            and 
            (#messageHasData("numberword") or #messageHasData("date_time", { year: true }));
    }
}
