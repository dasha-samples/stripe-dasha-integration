library

type ProductInfo = {
    product_id: string;
    description: string;
    price: number;
};

type Date = {
    month: string;
    date: number;
    day_of_week: string;
};

type ShippingInfo = {
    address_name: string;
    taxes: number;
    price: number;
    time_days: number;
    delivery_date: Date;
};

type ExpDate = {
    exp_month_str: string;
    exp_month: number;
    exp_year: number;
};

type PaymentResult = {
    success: boolean;
    error: string?;
};

// type CardInfo = {
//     c_number: string;
//     c_name: string;
//     c_exp_date: ExpDate;
//     c_cvv_code: number;
//     //zip_code: string;
// };
