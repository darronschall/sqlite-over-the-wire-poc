# README

[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This example Rails server code illustrates returning a populated SQLite database over the wire. See
[the parent README.md](../README.md) for more information.

## System requirements

* ruby 3.0.1
* postgresql 13.2

# Installation

* `bundle install`
* `bin/rails db:setup`

# Start the server

* `bin/rails s`

# Interacting with the Server

Get the JSON response:

```bash
curl -H "Accept: application/json" -w '%{time_total}\n' -s -o result.json http://127.0.0.1:3000/api/v1/books
```

Examine result:

```bash
cat result.json
```

Get the SQLite response:

```bash
 curl -H "Accept: application/x-sqlite3" -w '%{time_total}\n' -s -o result.sqlite http://127.0.0.1:3000/api/v1/books
```

Examine result:

```bash
sqlite3 result.sqlite
```

First pass of metrics to measure total response time:

```bash
curl -H "Accept: application/json" -s -w '%{time_total}\n' -o result.json http://127.0.0.1:3000/api/v1/books
# 0.068418
# 0.042668
# 0.025806
# 0.032018
# 0.042215
# 0.027656
# 0.042839
# 0.035897
# 0.042064
# 0.025089


curl -H "Accept: application/x-sqlite3" -s -w '%{time_total}\n' -o result.sqlite http://127.0.0.1:3000/api/v1/books
# 0.043872
# 0.027450
# 0.043389
# 0.041776
# 0.027652
# 0.026321
# 0.028183
# 0.045139
# 0.041162
# 0.027638
```

Payload size:

```bash
% ls -al result.*                                                                                                  
-rw-r--r--  1 darron  staff   7398 May 14 11:14 result.json
-rw-r--r--  1 darron  staff  36864 May 14 11:14 result.sqlite
```
