elibphonenumber
===============
[![Build Status](https://travis-ci.org/silviucpp/elibphonenumber.svg?branch=master)](https://travis-ci.org/silviucpp/elibphonenumber)

Erlang port of [libphonenumber][1]

## Notes

- This project is active. I'm doing updates very offen because I see the original author is no longer maintaining it.
- Compatible with both `rebar` and `rebar3` or `hex`
- To change the `libphonenumber` version modify in `rebar.config` the `TAG` argument sent to `make`

## Compile

In order to compile you need to make sure all dependencies needed to build `libphonenumber` are already installed.

Next you can find a resume for each operating system where library was tested but in case you encounter problems you can 
consult as well the documentation from building `libphonenumber` located [here][2]

##### Ubuntu

On the latest versions it's enough to do:

```bash
sudo apt-get install cmake cmake-curses-gui libgtest-dev libre2-dev libicu-dev 
sudo apt-get install libboost-dev libboost-thread-dev libboost-system-dev
sudo apt-get install libprotobuf-dev protobuf-compiler
```

In case you are using `Ubuntu 14.04` also follow the following steps in order to install `libre` and `cmake-3`:

```bash
sudo apt-get remove cmake cmake-data
sudo -E add-apt-repository -y ppa:george-edison55/cmake-3.x
sudo -E apt-get update
sudo apt-get install cmake

wget http://mt.archive.ubuntu.com/ubuntu/pool/universe/r/re2/libre2-1_20140304+dfsg-2_amd64.deb -O libre2-1.deb
wget http://es.archive.ubuntu.com/ubuntu/pool/universe/r/re2/libre2-dev_20140304+dfsg-2_amd64.deb -O libre2-dev.deb
sudo dpkg -i libre2*.deb
```

##### Debian 9 (Stretch)

The same as for Ubuntu

```bash
sudo apt-get install cmake cmake-curses-gui libgtest-dev libre2-dev libicu-dev 
sudo apt-get install libboost-dev libboost-thread-dev libboost-system-dev
sudo apt-get install libprotobuf-dev protobuf-compiler
```

##### CentOS 7

Enable [EPEL][3] (for RE2 & gtest):
```bash
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```

And install packages:
```bash
sudo yum install cmake git boost-devel gtest-devel libicu-devel protobuf-devel protobuf-compiler re2-devel
```

##### Mac Os

On `Mac OS` make sure you have `brew` installed and rebar will automatically install all necessary dependencies.
 
## Get carrier for number
    
In order to do this make sure the application is started then use `phonenumber_to_carrier:carrier_for_number/2` method    
    
```erlang 
application:ensure_all_started(elibphonenumber).
phonenumber_to_carrier:carrier_for_number(<<"44743655551">>, <<"en">>).
```    

## Run the tests

```bash
rebar3 eunit
```

[1]: https://github.com/googlei18n/libphonenumber
[2]: https://github.com/googlei18n/libphonenumber/blob/master/cpp/README
[3]: https://fedoraproject.org/wiki/EPEL#Quickstart