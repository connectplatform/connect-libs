-module(phonenumber_to_carrier_test).

-include_lib("eunit/include/eunit.hrl").

carrier_for_number_test() ->
    application:ensure_all_started(elibphonenumber),
    <<"Vodafone">> = phonenumber_to_carrier:carrier_for_number(<<"44743655551">>, <<"en">>),
    <<>> = phonenumber_to_carrier:carrier_for_number(<<"AAAA">>, <<"en">>).

