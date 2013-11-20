money-api
=========

Provide a server using OpenExchangeRates data for converting currencies nicely

To use this server:
 1. Create an API key on OpenExchangeRates.org
 2. Set two environment variables:
  1. `MONEY_PORT` - port number to run on
  2. `MONEY_KEY` - the API key from above
 3. Compile & run using `coffee -c index.coffee && node index.js`
 4. Or, run directly using `coffee index.coffee`

This server is essentially a caching wrapper around the result from OER to get around the 1000/month limit, as well as providing two routes for using the data.

The routes available are described on the root path `GET /`
