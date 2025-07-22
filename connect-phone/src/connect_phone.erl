%%%-------------------------------------------------------------------
%%% @doc Connect Platform Phone Number Validation
%%%
%%% Pure Erlang implementation for phone number validation and normalization,
%%% specifically designed for using phone numbers as account identifiers.
%%%
%%% Key Features:
%%% - Ensures phone numbers are complete (no missing digits)
%%% - Normalizes to consistent E164 format for account IDs
%%% - Validates international and domestic numbers
%%% - Pure Erlang - no dependencies
%%%
%%% Built on marinakr/libphonenumber_erlang
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(connect_phone).

-export([
    % Core Account ID Functions
    normalize_account_id/1,
    validate_account_id/1,
    
    % Phone Number Validation
    is_valid/1,
    get_phone_info/1,
    
    % Utility Functions
    format_e164/1,
    extract_country_info/1,
    
    % OTP 27 Enhanced Functions
    get_phone_info_json/1,
    validate_with_enhanced_errors/1,
    batch_validate/1
]).

-type phone_number() :: binary().
-type account_id() :: nonempty_binary().
-type validation_result() :: {ok, account_id()} | {error, atom()}.
-type phone_info() :: #{
    phone := binary(),
    valid := boolean(),
    country_metadata => #{
        code := binary(),
        id := <<_:16,_:_*40>>,
        name := <<_:40,_:_*8>>
    },
    errors => [invalid_country_code_length | invalid_format | invalid_length_for_country | 
               invalid_national_number | national_number_too_long | national_number_too_short | 
               non_numeric_country_code | non_numeric_national_number | requires_country_code]
}.

-export_type([
    phone_number/0,
    account_id/0,
    validation_result/0,
    phone_info/0
]).

%%%===================================================================
%%% Account ID Functions (Primary Use Case)
%%%===================================================================

%% @doc Normalize a phone number to use as an account ID
%% Ensures the number is complete and in E164 format
%% This is the primary function for account registration/login
-spec normalize_account_id(phone_number()) -> validation_result().
normalize_account_id(PhoneNumber) when is_binary(PhoneNumber) ->
    try
        % Clean the input
        CleanNumber = clean_phone_number(PhoneNumber),
        
        % Validate using pure Erlang patterns
        case validate_phone_pattern(CleanNumber) of
            {ok, NormalizedNumber} ->
                % Additional completeness check
                case validate_completeness(NormalizedNumber) of
                    {ok, CompleteNumber} -> {ok, CompleteNumber};
                    {error, _} = Error -> Error
                end;
            {error, _} = Error -> Error
        end
    catch
        _:_ ->
            {error, normalization_failed}
    end;
normalize_account_id(_PhoneNumber) ->
    {error, invalid_input}.

%% @doc Validate that a phone number can be used as an account ID
%% Same as normalize_account_id but with a clearer name for validation context
-spec validate_account_id(binary()) -> validation_result().
validate_account_id(PhoneNumber) ->
    normalize_account_id(PhoneNumber).

%%%===================================================================
%%% Phone Number Validation Functions
%%%===================================================================

%% @doc Check if a phone number is valid
-spec is_valid(term()) -> boolean().
is_valid(PhoneNumber) when is_binary(PhoneNumber) ->
    try
        CleanNumber = clean_phone_number(PhoneNumber),
        case validate_phone_pattern(CleanNumber) of
            {ok, _} -> true;
            {error, _} -> false
        end
    catch
        _:_ -> false
    end;
is_valid(_) -> false.

%% @doc Get detailed phone number information
-spec get_phone_info(term()) -> phone_info() | {error, invalid_input | phone_info_failed}.
get_phone_info(PhoneNumber) when is_binary(PhoneNumber) ->
    try
        CleanNumber = clean_phone_number(PhoneNumber),
        case validate_phone_pattern(CleanNumber) of
            {ok, NormalizedNumber} ->
                CountryInfo = extract_country_from_number(NormalizedNumber),
                #{
                    phone => NormalizedNumber,
                    valid => true,
                    country_metadata => CountryInfo
                };
            {error, Reason} ->
                #{
                    phone => CleanNumber,
                    valid => false,
                    errors => [Reason]
                }
        end
    catch
        _:_ -> {error, phone_info_failed}
    end;
get_phone_info(_) -> {error, invalid_input}.

%%%===================================================================
%%% Utility Functions
%%%===================================================================

%% @doc Format a phone number to E164 format
-spec format_e164(term()) -> {ok, nonempty_binary()} | {error, atom()}.
format_e164(PhoneNumber) when is_binary(PhoneNumber) ->
    case normalize_account_id(PhoneNumber) of
        {ok, E164Number} -> {ok, E164Number};
        {error, _} = Error -> Error
    end;
format_e164(_) -> {error, invalid_input}.

%% @doc Extract country information from a phone number
-spec extract_country_info(term()) -> {ok, #{code := binary(), id := <<_:16,_:_*40>>, name := <<_:40,_:_*8>>}} | {error, invalid_input | invalid_phone_number | no_country_info | phone_info_failed}.
extract_country_info(PhoneNumber) when is_binary(PhoneNumber) ->
    case get_phone_info(PhoneNumber) of
        #{valid := true, country_metadata := CountryInfo} ->
            {ok, CountryInfo};
        #{valid := false} ->
            {error, invalid_phone_number};
        {error, _} = Error ->
            Error;
        _ ->
            {error, no_country_info}
    end;
extract_country_info(_) -> {error, invalid_input}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private
%% @doc Clean phone number input by removing common formatting
-spec clean_phone_number(binary()) -> binary().
clean_phone_number(PhoneNumber) ->
    % First check for malformed patterns that should be rejected
    case binary:match(PhoneNumber, [<<"+-">>, <<"-+">>, <<"++">>]) of
        nomatch ->
            % Remove common formatting characters but preserve + for international
            Cleaned = re:replace(PhoneNumber, "[\\s\\-\\(\\)\\.\\#]", "", [global, {return, binary}]),
            % Ensure we don't have multiple + signs
            case binary:split(Cleaned, <<"+">>, [global]) of
                [<<>>, Rest] -> <<"+", Rest/binary>>;  % Single + at start
                [Number] -> Number;                     % No + sign
                _ -> Cleaned                            % Multiple +, return as-is for error handling
            end;
        _ ->
            % Return malformed input as-is to be caught by validation
            PhoneNumber
    end.

%% @private
%% @doc Validate phone number pattern and normalize to E164 format
-spec validate_phone_pattern(binary()) -> {ok, nonempty_binary()} | {error, invalid_country_code_length | invalid_format | invalid_length_for_country | invalid_national_number | national_number_too_long | national_number_too_short | non_numeric_country_code | non_numeric_national_number | requires_country_code}.
validate_phone_pattern(PhoneNumber) when is_binary(PhoneNumber) ->
    case PhoneNumber of
        <<"+", Rest/binary>> ->
            % Already in international format
            validate_international_format(<<"+", Rest/binary>>);
        _ ->
            % Not in international format - reject for account ID safety
            {error, requires_country_code}
    end.

%% @private
%% @doc Validate international format (+CCNNNNNNN)
-spec validate_international_format(<<_:8,_:_*1>>) -> {ok, nonempty_binary()} | {error, invalid_country_code_length | invalid_format | invalid_length_for_country | invalid_national_number | national_number_too_long | national_number_too_short | non_numeric_country_code | non_numeric_national_number}.
validate_international_format(<<"+", Rest/binary>>) ->
    case re:run(Rest, "^([0-9]{1,3})([0-9]{7,10})$") of
        {match, [_, {CCStart, CCLen}, {NNStart, NNLen}]} ->
            CountryCode = binary:part(Rest, CCStart, CCLen),
            NationalNumber = binary:part(Rest, NNStart, NNLen),
            
            case validate_country_code(CountryCode) of
                {ok, ValidCC} ->
                    case validate_national_number(NationalNumber, ValidCC) of
                        {ok, ValidNN} ->
                            {ok, <<"+", ValidCC/binary, ValidNN/binary>>};
                        {error, _} = Error -> Error
                    end;
                {error, _} = Error -> Error
            end;
        nomatch ->
            {error, invalid_format}
    end;
validate_international_format(_) ->
    {error, invalid_format}.

%% @private
%% @doc Validate country code (1-3 digits)
-spec validate_country_code(binary()) -> {ok, binary()} | {error, invalid_country_code_length | non_numeric_country_code}.
validate_country_code(CC) when byte_size(CC) >= 1, byte_size(CC) =< 3 ->
    case re:run(CC, "^[0-9]+$") of
        {match, _} ->
            % Basic known country code validation
            case CC of
                <<"1">> -> {ok, CC};      % US/Canada
                <<"7">> -> {ok, CC};      % Russia
                <<"20">> -> {ok, CC};     % Egypt
                <<"27">> -> {ok, CC};     % South Africa
                <<"30">> -> {ok, CC};     % Greece
                <<"31">> -> {ok, CC};     % Netherlands
                <<"32">> -> {ok, CC};     % Belgium
                <<"33">> -> {ok, CC};     % France
                <<"34">> -> {ok, CC};     % Spain
                <<"36">> -> {ok, CC};     % Hungary
                <<"39">> -> {ok, CC};     % Italy
                <<"40">> -> {ok, CC};     % Romania
                <<"41">> -> {ok, CC};     % Switzerland
                <<"43">> -> {ok, CC};     % Austria
                <<"44">> -> {ok, CC};     % UK
                <<"45">> -> {ok, CC};     % Denmark
                <<"46">> -> {ok, CC};     % Sweden
                <<"47">> -> {ok, CC};     % Norway
                <<"48">> -> {ok, CC};     % Poland
                <<"49">> -> {ok, CC};     % Germany
                <<"51">> -> {ok, CC};     % Peru
                <<"52">> -> {ok, CC};     % Mexico
                <<"53">> -> {ok, CC};     % Cuba
                <<"54">> -> {ok, CC};     % Argentina
                <<"55">> -> {ok, CC};     % Brazil
                <<"56">> -> {ok, CC};     % Chile
                <<"57">> -> {ok, CC};     % Colombia
                <<"58">> -> {ok, CC};     % Venezuela
                <<"60">> -> {ok, CC};     % Malaysia
                <<"61">> -> {ok, CC};     % Australia
                <<"62">> -> {ok, CC};     % Indonesia
                <<"63">> -> {ok, CC};     % Philippines
                <<"64">> -> {ok, CC};     % New Zealand
                <<"65">> -> {ok, CC};     % Singapore
                <<"66">> -> {ok, CC};     % Thailand
                <<"81">> -> {ok, CC};     % Japan
                <<"82">> -> {ok, CC};     % South Korea
                <<"84">> -> {ok, CC};     % Vietnam
                <<"86">> -> {ok, CC};     % China
                <<"90">> -> {ok, CC};     % Turkey
                <<"91">> -> {ok, CC};     % India
                <<"92">> -> {ok, CC};     % Pakistan
                <<"93">> -> {ok, CC};     % Afghanistan
                <<"94">> -> {ok, CC};     % Sri Lanka
                <<"95">> -> {ok, CC};     % Myanmar
                <<"98">> -> {ok, CC};     % Iran
                <<"212">> -> {ok, CC};    % Morocco
                <<"213">> -> {ok, CC};    % Algeria
                <<"216">> -> {ok, CC};    % Tunisia
                <<"218">> -> {ok, CC};    % Libya
                <<"220">> -> {ok, CC};    % Gambia
                <<"221">> -> {ok, CC};    % Senegal
                <<"222">> -> {ok, CC};    % Mauritania
                <<"223">> -> {ok, CC};    % Mali
                <<"224">> -> {ok, CC};    % Guinea
                <<"225">> -> {ok, CC};    % Ivory Coast
                <<"226">> -> {ok, CC};    % Burkina Faso
                <<"227">> -> {ok, CC};    % Niger
                <<"228">> -> {ok, CC};    % Togo
                <<"229">> -> {ok, CC};    % Benin
                <<"230">> -> {ok, CC};    % Mauritius
                <<"231">> -> {ok, CC};    % Liberia
                <<"232">> -> {ok, CC};    % Sierra Leone
                <<"233">> -> {ok, CC};    % Ghana
                <<"234">> -> {ok, CC};    % Nigeria
                <<"235">> -> {ok, CC};    % Chad
                <<"236">> -> {ok, CC};    % Central African Republic
                <<"237">> -> {ok, CC};    % Cameroon
                <<"238">> -> {ok, CC};    % Cape Verde
                <<"239">> -> {ok, CC};    % São Tomé and Príncipe
                <<"240">> -> {ok, CC};    % Equatorial Guinea
                <<"241">> -> {ok, CC};    % Gabon
                <<"242">> -> {ok, CC};    % Republic of the Congo
                <<"243">> -> {ok, CC};    % Democratic Republic of the Congo
                <<"244">> -> {ok, CC};    % Angola
                <<"245">> -> {ok, CC};    % Guinea-Bissau
                <<"246">> -> {ok, CC};    % British Indian Ocean Territory
                <<"248">> -> {ok, CC};    % Seychelles
                <<"249">> -> {ok, CC};    % Sudan
                <<"250">> -> {ok, CC};    % Rwanda
                <<"251">> -> {ok, CC};    % Ethiopia
                <<"252">> -> {ok, CC};    % Somalia
                <<"253">> -> {ok, CC};    % Djibouti
                <<"254">> -> {ok, CC};    % Kenya
                <<"255">> -> {ok, CC};    % Tanzania
                <<"256">> -> {ok, CC};    % Uganda
                <<"257">> -> {ok, CC};    % Burundi
                <<"258">> -> {ok, CC};    % Mozambique
                <<"260">> -> {ok, CC};    % Zambia
                <<"261">> -> {ok, CC};    % Madagascar
                <<"262">> -> {ok, CC};    % Réunion
                <<"263">> -> {ok, CC};    % Zimbabwe
                <<"264">> -> {ok, CC};    % Namibia
                <<"265">> -> {ok, CC};    % Malawi
                <<"266">> -> {ok, CC};    % Lesotho
                <<"267">> -> {ok, CC};    % Botswana
                <<"268">> -> {ok, CC};    % Swaziland
                <<"269">> -> {ok, CC};    % Comoros
                <<"290">> -> {ok, CC};    % Saint Helena
                <<"291">> -> {ok, CC};    % Eritrea
                <<"297">> -> {ok, CC};    % Aruba
                <<"298">> -> {ok, CC};    % Faroe Islands
                <<"299">> -> {ok, CC};    % Greenland
                <<"350">> -> {ok, CC};    % Gibraltar
                <<"351">> -> {ok, CC};    % Portugal
                <<"352">> -> {ok, CC};    % Luxembourg
                <<"353">> -> {ok, CC};    % Ireland
                <<"354">> -> {ok, CC};    % Iceland
                <<"355">> -> {ok, CC};    % Albania
                <<"356">> -> {ok, CC};    % Malta
                <<"357">> -> {ok, CC};    % Cyprus
                <<"358">> -> {ok, CC};    % Finland
                <<"359">> -> {ok, CC};    % Bulgaria
                <<"370">> -> {ok, CC};    % Lithuania
                <<"371">> -> {ok, CC};    % Latvia
                <<"372">> -> {ok, CC};    % Estonia
                <<"373">> -> {ok, CC};    % Moldova
                <<"374">> -> {ok, CC};    % Armenia
                <<"375">> -> {ok, CC};    % Belarus
                <<"376">> -> {ok, CC};    % Andorra
                <<"377">> -> {ok, CC};    % Monaco
                <<"378">> -> {ok, CC};    % San Marino
                <<"380">> -> {ok, CC};    % Ukraine
                <<"381">> -> {ok, CC};    % Serbia
                <<"382">> -> {ok, CC};    % Montenegro
                <<"383">> -> {ok, CC};    % Kosovo
                <<"385">> -> {ok, CC};    % Croatia
                <<"386">> -> {ok, CC};    % Slovenia
                <<"387">> -> {ok, CC};    % Bosnia and Herzegovina
                <<"389">> -> {ok, CC};    % North Macedonia
                <<"420">> -> {ok, CC};    % Czech Republic
                <<"421">> -> {ok, CC};    % Slovakia
                <<"423">> -> {ok, CC};    % Liechtenstein
                <<"500">> -> {ok, CC};    % Falkland Islands
                <<"501">> -> {ok, CC};    % Belize
                <<"502">> -> {ok, CC};    % Guatemala
                <<"503">> -> {ok, CC};    % El Salvador
                <<"504">> -> {ok, CC};    % Honduras
                <<"505">> -> {ok, CC};    % Nicaragua
                <<"506">> -> {ok, CC};    % Costa Rica
                <<"507">> -> {ok, CC};    % Panama
                <<"508">> -> {ok, CC};    % Saint Pierre and Miquelon
                <<"509">> -> {ok, CC};    % Haiti
                <<"590">> -> {ok, CC};    % Guadeloupe
                <<"591">> -> {ok, CC};    % Bolivia
                <<"592">> -> {ok, CC};    % Guyana
                <<"593">> -> {ok, CC};    % Ecuador
                <<"594">> -> {ok, CC};    % French Guiana
                <<"595">> -> {ok, CC};    % Paraguay
                <<"596">> -> {ok, CC};    % Martinique
                <<"597">> -> {ok, CC};    % Suriname
                <<"598">> -> {ok, CC};    % Uruguay
                <<"599">> -> {ok, CC};    % Netherlands Antilles
                <<"670">> -> {ok, CC};    % East Timor
                <<"672">> -> {ok, CC};    % Australian External Territories
                <<"673">> -> {ok, CC};    % Brunei
                <<"674">> -> {ok, CC};    % Nauru
                <<"675">> -> {ok, CC};    % Papua New Guinea
                <<"676">> -> {ok, CC};    % Tonga
                <<"677">> -> {ok, CC};    % Solomon Islands
                <<"678">> -> {ok, CC};    % Vanuatu
                <<"679">> -> {ok, CC};    % Fiji
                <<"680">> -> {ok, CC};    % Palau
                <<"681">> -> {ok, CC};    % Wallis and Futuna
                <<"682">> -> {ok, CC};    % Cook Islands
                <<"683">> -> {ok, CC};    % Niue
                <<"684">> -> {ok, CC};    % American Samoa
                <<"685">> -> {ok, CC};    % Samoa
                <<"686">> -> {ok, CC};    % Kiribati
                <<"687">> -> {ok, CC};    % New Caledonia
                <<"688">> -> {ok, CC};    % Tuvalu
                <<"689">> -> {ok, CC};    % French Polynesia
                <<"690">> -> {ok, CC};    % Tokelau
                <<"691">> -> {ok, CC};    % Federated States of Micronesia
                <<"692">> -> {ok, CC};    % Marshall Islands
                <<"850">> -> {ok, CC};    % North Korea
                <<"852">> -> {ok, CC};    % Hong Kong
                <<"853">> -> {ok, CC};    % Macau
                <<"855">> -> {ok, CC};    % Cambodia
                <<"856">> -> {ok, CC};    % Laos
                <<"880">> -> {ok, CC};    % Bangladesh
                <<"886">> -> {ok, CC};    % Taiwan
                <<"960">> -> {ok, CC};    % Maldives
                <<"961">> -> {ok, CC};    % Lebanon
                <<"962">> -> {ok, CC};    % Jordan
                <<"963">> -> {ok, CC};    % Syria
                <<"964">> -> {ok, CC};    % Iraq
                <<"965">> -> {ok, CC};    % Kuwait
                <<"966">> -> {ok, CC};    % Saudi Arabia
                <<"967">> -> {ok, CC};    % Yemen
                <<"968">> -> {ok, CC};    % Oman
                <<"970">> -> {ok, CC};    % Palestine
                <<"971">> -> {ok, CC};    % United Arab Emirates
                <<"972">> -> {ok, CC};    % Israel
                <<"973">> -> {ok, CC};    % Bahrain
                <<"974">> -> {ok, CC};    % Qatar
                <<"975">> -> {ok, CC};    % Bhutan
                <<"976">> -> {ok, CC};    % Mongolia
                <<"977">> -> {ok, CC};    % Nepal
                <<"992">> -> {ok, CC};    % Tajikistan
                <<"993">> -> {ok, CC};    % Turkmenistan
                <<"994">> -> {ok, CC};    % Azerbaijan
                <<"995">> -> {ok, CC};    % Georgia
                <<"996">> -> {ok, CC};    % Kyrgyzstan
                <<"998">> -> {ok, CC};    % Uzbekistan
                _ -> 
                    % Allow other numeric country codes but log them
                    logger:info("Unknown country code: ~p", [CC]),
                    {ok, CC}
            end;
        nomatch ->
            {error, non_numeric_country_code}
    end;
validate_country_code(_) ->
    {error, invalid_country_code_length}.

%% @private
%% @doc Validate national number part (7-10 digits for most countries)
-spec validate_national_number(binary(), binary()) -> {ok, binary()} | {error, invalid_length_for_country | invalid_national_number | national_number_too_long | national_number_too_short | non_numeric_national_number}.
validate_national_number(NN, CountryCode) when byte_size(NN) >= 7, byte_size(NN) =< 10 ->
    case re:run(NN, "^[0-9]+$") of
        {match, _} ->
            % Additional length validation based on country code
            case is_valid_length_for_country(CountryCode, byte_size(NN)) of
                true -> {ok, NN};
                false -> {error, invalid_length_for_country}
            end;
        nomatch ->
            {error, non_numeric_national_number}
    end;
validate_national_number(NN, _CountryCode) ->
    Len = byte_size(NN),
    if
        Len < 7 -> {error, national_number_too_short};
        Len > 10 -> {error, national_number_too_long};
        true -> {error, invalid_national_number}
    end.

%% @private
%% @doc Check if national number length is valid for the country
-spec is_valid_length_for_country(binary(), non_neg_integer()) -> boolean().
is_valid_length_for_country(<<"1">>, Len) -> Len == 10;      % US/Canada - exactly 10 digits
is_valid_length_for_country(<<"44">>, Len) -> Len >= 8 andalso Len =< 10;  % UK - 8-10 digits
is_valid_length_for_country(<<"49">>, Len) -> Len >= 8 andalso Len =< 10;  % Germany - 8-10 digits
is_valid_length_for_country(<<"33">>, Len) -> Len == 9;      % France - exactly 9 digits
is_valid_length_for_country(_, Len) -> Len >= 7 andalso Len =< 10.  % Default: 7-10 digits

%% @private
%% @doc Validate completeness of a normalized phone number
-spec validate_completeness(nonempty_binary()) -> {ok, nonempty_binary()} | {error, invalid_format | missing_country_code | number_too_long | number_too_short}.
validate_completeness(E164Number) when is_binary(E164Number) ->
    case E164Number of
        <<"+", Rest/binary>> when byte_size(Rest) >= 7, byte_size(Rest) =< 15 ->
            case re:run(Rest, "^[0-9]+$") of
                {match, _} -> {ok, E164Number};
                nomatch -> {error, invalid_format}
            end;
        <<"+", Rest/binary>> ->
            Len = byte_size(Rest),
            if
                Len < 7 -> {error, number_too_short};
                Len > 15 -> {error, number_too_long};
                true -> {error, invalid_format}
            end;
        _ ->
            {error, missing_country_code}
    end.

%% @private
%% @doc Extract country information from a phone number
-spec extract_country_from_number(nonempty_binary()) -> #{code := binary(), id := <<_:16,_:_*40>>, name := <<_:40,_:_*8>>}.
extract_country_from_number(<<"+", Rest/binary>>) ->
    % Extract country code and map to country info
    case extract_country_code_from_number(Rest) of
        {ok, CC, _NN} ->
            case country_code_to_info(CC) of
                {ok, Info} -> Info;
                {error, _} -> #{code => CC, id => <<"UNKNOWN">>, name => <<"Unknown Country">>}
            end;
        {error, _} ->
            #{code => <<"0">>, id => <<"INVALID">>, name => <<"Invalid Number">>}
    end;
extract_country_from_number(_) ->
    #{code => <<"0">>, id => <<"INVALID">>, name => <<"Invalid Number">>}.

%% @private
%% @doc Extract country code from the number part
-spec extract_country_code_from_number(binary()) -> {ok, binary(), binary()} | {error, insufficient_digits | invalid_country_code_length | invalid_national_number_length | non_numeric_country_code}.
extract_country_code_from_number(Number) ->
    % Try 1-digit country codes first (most common), then 2-digit, then 3-digit
    case try_extract_cc(Number, 1) of
        {ok, CC, NN} -> {ok, CC, NN};
        {error, _} ->
            case try_extract_cc(Number, 2) of
                {ok, CC, NN} -> {ok, CC, NN};
                {error, _} ->
                    try_extract_cc(Number, 3)
            end
    end.

%% @private
%% @doc Try to extract country code of specific length
-spec try_extract_cc(binary(), 1 | 2 | 3) -> {ok, binary(), binary()} | {error, insufficient_digits | invalid_country_code_length | invalid_national_number_length | non_numeric_country_code}.
try_extract_cc(Number, CCLen) when byte_size(Number) >= CCLen + 7 ->
    CC = binary:part(Number, 0, CCLen),
    NN = binary:part(Number, CCLen, byte_size(Number) - CCLen),
    case validate_country_code(CC) of
        {ok, ValidCC} ->
            % Check if the remaining national number is valid length
            case byte_size(NN) >= 7 andalso byte_size(NN) =< 10 of
                true -> {ok, ValidCC, NN};
                false -> {error, invalid_national_number_length}
            end;
        {error, _} = Error -> Error
    end;
try_extract_cc(_, _) ->
    {error, insufficient_digits}.

%% @private
%% @doc Map country code to country information
-spec country_code_to_info(binary()) -> {ok, #{code := nonempty_binary(), id := <<_:16>>, name := <<_:40,_:_*8>>}} | {error, unknown_country_code}.
country_code_to_info(CC) ->
    case CC of
        <<"1">> -> {ok, #{code => <<"1">>, id => <<"US">>, name => <<"United States">>}};
        <<"44">> -> {ok, #{code => <<"44">>, id => <<"GB">>, name => <<"United Kingdom">>}};
        <<"49">> -> {ok, #{code => <<"49">>, id => <<"DE">>, name => <<"Germany">>}};
        <<"33">> -> {ok, #{code => <<"33">>, id => <<"FR">>, name => <<"France">>}};
        <<"39">> -> {ok, #{code => <<"39">>, id => <<"IT">>, name => <<"Italy">>}};
        <<"34">> -> {ok, #{code => <<"34">>, id => <<"ES">>, name => <<"Spain">>}};
        <<"31">> -> {ok, #{code => <<"31">>, id => <<"NL">>, name => <<"Netherlands">>}};
        <<"41">> -> {ok, #{code => <<"41">>, id => <<"CH">>, name => <<"Switzerland">>}};
        <<"43">> -> {ok, #{code => <<"43">>, id => <<"AT">>, name => <<"Austria">>}};
        <<"32">> -> {ok, #{code => <<"32">>, id => <<"BE">>, name => <<"Belgium">>}};
        <<"45">> -> {ok, #{code => <<"45">>, id => <<"DK">>, name => <<"Denmark">>}};
        <<"46">> -> {ok, #{code => <<"46">>, id => <<"SE">>, name => <<"Sweden">>}};
        <<"47">> -> {ok, #{code => <<"47">>, id => <<"NO">>, name => <<"Norway">>}};
        <<"358">> -> {ok, #{code => <<"358">>, id => <<"FI">>, name => <<"Finland">>}};
        <<"48">> -> {ok, #{code => <<"48">>, id => <<"PL">>, name => <<"Poland">>}};
        <<"420">> -> {ok, #{code => <<"420">>, id => <<"CZ">>, name => <<"Czech Republic">>}};
        <<"421">> -> {ok, #{code => <<"421">>, id => <<"SK">>, name => <<"Slovakia">>}};
        <<"36">> -> {ok, #{code => <<"36">>, id => <<"HU">>, name => <<"Hungary">>}};
        <<"40">> -> {ok, #{code => <<"40">>, id => <<"RO">>, name => <<"Romania">>}};
        <<"359">> -> {ok, #{code => <<"359">>, id => <<"BG">>, name => <<"Bulgaria">>}};
        <<"385">> -> {ok, #{code => <<"385">>, id => <<"HR">>, name => <<"Croatia">>}};
        <<"386">> -> {ok, #{code => <<"386">>, id => <<"SI">>, name => <<"Slovenia">>}};
        <<"370">> -> {ok, #{code => <<"370">>, id => <<"LT">>, name => <<"Lithuania">>}};
        <<"371">> -> {ok, #{code => <<"371">>, id => <<"LV">>, name => <<"Latvia">>}};
        <<"372">> -> {ok, #{code => <<"372">>, id => <<"EE">>, name => <<"Estonia">>}};
        <<"380">> -> {ok, #{code => <<"380">>, id => <<"UA">>, name => <<"Ukraine">>}};
        <<"7">> -> {ok, #{code => <<"7">>, id => <<"RU">>, name => <<"Russia">>}};
        <<"81">> -> {ok, #{code => <<"81">>, id => <<"JP">>, name => <<"Japan">>}};
        <<"82">> -> {ok, #{code => <<"82">>, id => <<"KR">>, name => <<"South Korea">>}};
        <<"86">> -> {ok, #{code => <<"86">>, id => <<"CN">>, name => <<"China">>}};
        <<"91">> -> {ok, #{code => <<"91">>, id => <<"IN">>, name => <<"India">>}};
        <<"61">> -> {ok, #{code => <<"61">>, id => <<"AU">>, name => <<"Australia">>}};
        <<"64">> -> {ok, #{code => <<"64">>, id => <<"NZ">>, name => <<"New Zealand">>}};
        <<"55">> -> {ok, #{code => <<"55">>, id => <<"BR">>, name => <<"Brazil">>}};
        <<"52">> -> {ok, #{code => <<"52">>, id => <<"MX">>, name => <<"Mexico">>}};
        <<"54">> -> {ok, #{code => <<"54">>, id => <<"AR">>, name => <<"Argentina">>}};
        <<"56">> -> {ok, #{code => <<"56">>, id => <<"CL">>, name => <<"Chile">>}};
        <<"57">> -> {ok, #{code => <<"57">>, id => <<"CO">>, name => <<"Colombia">>}};
        <<"351">> -> {ok, #{code => <<"351">>, id => <<"PT">>, name => <<"Portugal">>}};
        <<"353">> -> {ok, #{code => <<"353">>, id => <<"IE">>, name => <<"Ireland">>}};
        <<"30">> -> {ok, #{code => <<"30">>, id => <<"GR">>, name => <<"Greece">>}};
        <<"90">> -> {ok, #{code => <<"90">>, id => <<"TR">>, name => <<"Turkey">>}};
        <<"972">> -> {ok, #{code => <<"972">>, id => <<"IL">>, name => <<"Israel">>}};
        <<"27">> -> {ok, #{code => <<"27">>, id => <<"ZA">>, name => <<"South Africa">>}};
        <<"20">> -> {ok, #{code => <<"20">>, id => <<"EG">>, name => <<"Egypt">>}};
        <<"234">> -> {ok, #{code => <<"234">>, id => <<"NG">>, name => <<"Nigeria">>}};
        <<"254">> -> {ok, #{code => <<"254">>, id => <<"KE">>, name => <<"Kenya">>}};
        <<"60">> -> {ok, #{code => <<"60">>, id => <<"MY">>, name => <<"Malaysia">>}};
        <<"65">> -> {ok, #{code => <<"65">>, id => <<"SG">>, name => <<"Singapore">>}};
        <<"66">> -> {ok, #{code => <<"66">>, id => <<"TH">>, name => <<"Thailand">>}};
        <<"84">> -> {ok, #{code => <<"84">>, id => <<"VN">>, name => <<"Vietnam">>}};
        <<"63">> -> {ok, #{code => <<"63">>, id => <<"PH">>, name => <<"Philippines">>}};
        <<"62">> -> {ok, #{code => <<"62">>, id => <<"ID">>, name => <<"Indonesia">>}};
        _ -> {error, unknown_country_code}
    end.

%%%===================================================================
%%% OTP 27 Enhanced Functions
%%%===================================================================

%% @doc Get phone number information as JSON (OTP 27 json module)
-spec get_phone_info_json(term()) -> iodata() | {error, atom()}.
get_phone_info_json(PhoneNumber) ->
    case get_phone_info(PhoneNumber) of
        PhoneInfo when is_map(PhoneInfo) ->
            try 
                json:encode(PhoneInfo)
            catch
                error:Reason:Stacktrace ->
                    error({json_encode_error, Reason}, [PhoneNumber], #{
                        error_info => #{
                            module => ?MODULE,
                            function => get_phone_info_json,
                            arity => 1,
                            cause => "Failed to encode phone info as JSON",
                            stacktrace => Stacktrace
                        }
                    })
            end;
        {error, _} = Error -> Error
    end.

%% @doc Enhanced validation with improved OTP 27 error handling
-spec validate_with_enhanced_errors(term()) -> validation_result().
validate_with_enhanced_errors(PhoneNumber) ->
    try
        normalize_account_id(PhoneNumber)
    catch
        error:Reason:Stacktrace ->
            error({phone_validation_error, Reason}, [PhoneNumber], #{
                error_info => #{
                    module => ?MODULE,
                    function => validate_with_enhanced_errors,
                    arity => 1,
                    cause => "Phone number validation failed with enhanced error reporting",
                    stacktrace => Stacktrace,
                    input_type => type_of(PhoneNumber)
                }
            })
    end.

%% @doc Batch validate multiple phone numbers efficiently
-spec batch_validate([term()]) -> [{term(), validation_result()}].
batch_validate(PhoneNumbers) when is_list(PhoneNumbers) ->
    lists:map(fun(Phone) -> 
        {Phone, validate_with_enhanced_errors(Phone)} 
    end, PhoneNumbers);
batch_validate(_) ->
    [{invalid_input, {error, not_a_list}}].

%% @private
%% @doc Helper function to determine type of input
-spec type_of(term()) -> atom().
type_of(Term) when is_binary(Term) -> binary;
type_of(Term) when is_list(Term) -> list;
type_of(Term) when is_atom(Term) -> atom;
type_of(Term) when is_integer(Term) -> integer;
type_of(Term) when is_float(Term) -> float;
type_of(Term) when is_map(Term) -> map;
type_of(Term) when is_tuple(Term) -> tuple;
type_of(_) -> unknown. 