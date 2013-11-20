# CONFIG
port = process.env.MONEY_PORT or process.env.PORT
api_key = process.env.MONEY_KEY
api_limit = 1000 # max number of requests per MONTH

if not port? or isNaN port
	console.log 'Envvar MONEY_PORT must be set and be numeric'
	process.exit 0

if not api_key?
	console.log 'Envvar MONEY_KEY must be set to your openexchangerates API key'
	process.exit 0

# TTL = number of seconds the cache can live for, calculated as exactly the amount under which the api_limit won't be hit
ttl = Math.ceil (60 * 60 * 24 * 31) / (api_limit)

description = "A simple API for converting between two currencies. This is a simple caching wrapper around the data provided by http://openexchangerates.org/ with data updated every #{ttl} seconds."
disclaimer = "Exchange rates are provided for informational purposes only, and do not constitute financial advice of any kind. Although every attempt is made to ensure quality, NO guarantees are given whatsoever of accuracy, validity, availability, or fitness for any purpose - please use at your own risk. All usage is subject to your acceptance of the Terms and Conditions of Service, available at: https://openexchangerates.org/terms/"
license = "Data sourced from various providers with public-facing APIs; copyright may apply; resale is prohibited; no warranties given of any kind. All usage is subject to your acceptance of the License Agreement available at: https://openexchangerates.org/license/"

# EXEC

http = require 'http'
http.globalAgent.maxSockets = 64
q = require 'q'
restify = require 'restify'

server = restify.createServer()
client = restify.createJsonClient url: 'http://openexchangerates.org'
path = '/api/latest.json?app_id=' + api_key

# server modification
do ->
	# handle errors that are produced by Exceptions.
	# this makes it easier to produce errors in routes.
	server.on 'uncaughtException', (req, res, route, err) ->
		res.send 500, {
			status: "error",
			statusText: err.message or err
		}

	server.on 'NotFound', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'
	server.on 'MethodNotAllowed', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'
	server.on 'VersionNotAllowed', (req, res, next) -> next res.send 404, status: 'error', statusText: 'Endpoint not found'

	# logging
	server.on 'after', (req, res, route, err) ->
		time = new Date - res._time
		req.route ?= {}
		req.route.path ?= req._path ? '/'
		res.logMessage ?= ''
		console.log "#{req.method} #{req.route.path} (#{time}ms): #{res.statusCode} #{res.logMessage}"

		if res.statusCode.toString().slice(0,1) isnt '2'
			if res.bodyData and 0 > res.bodyData.indexOf '"Endpoint not found"'
				console.error res.bodyData

	# CORS
	server.use restify.CORS()
	server.use restify.fullResponse()

	# parse the query string only (no body, who cares)
	server.use restify.queryParser()

	server.listen port

# retrieve rates from server, using promises to eliminate multiple requests
do ->
	rates = {}
	global.getRates = (callback) ->
		if rates.expires > +new Date
			return callback rates.rates

		if not rates.promise
			defer = q.defer()
			rates.promise = defer.promise

			client.get path, (err, req, res, obj) ->
				if err
					throw err.body.description or err.body.message or err.message or err

				if not obj.rates
					throw 'Error: return did not contain rates'

				disclaimer = obj.disclaimer ? disclaimer
				license = obj.license ? license

				rates = obj
				rates.timestamp = new Date
				rates.expires = (ttl * 1000) + +new Date
				defer.resolve rates.rates

		return rates.promise.then callback

	global.getRatesAge = () ->
		time = rates.timestamp ? new Date
		age = (+new Date) - time
		return Math.round age / 1000

# the routes
server.get '/', (req, res, next) ->
	return next res.send {
		description: description,
		disclaimer: disclaimer,
		license: license,
		routes: {
			convert:
				description: 'Convert between two currencies'
				parameters:
					from: 'Currency code of the original currency'
					to: 'Currency code to convert to'
					amount: 'Amount to be converted (optional, default = 1)'
					precision: 'What precision to round to (optional, default = 2)'
			rates:
				description: 'List of rates known by the system'
		}
	}


server.get '/rates', (req, res, next) ->
	getRates (rates) ->
		if req.params.base?
			if not base_rate = rates[req.params.base]
				return next new restify.InvalidArgumentError "Unknown currency code '#{req.params.base}'."

			for code, rate of rates
				rates[code] = parseFloat (rate / base_rate).toFixed 5

		return next res.send rates

server.get '/convert', (req, res, next) ->
	if not req.params?.from?
		return next new restify.InvalidArgumentError 'Request requires a "from" currency'

	if not req.params?.to?
		return next new restify.InvalidArgumentError 'Request requires a "to" currency'

	from = req.params.from.toUpperCase()
	to = req.params.to.toUpperCase()

	amount = Number(req.params.amount ? req.params.value ? 1)
	if isNaN amount
		return next new restify.InvalidArgumentError 'Request "amount" must be a number.'

	precision = parseInt req.params.precision ? 2
	if isNaN precision
		return next new restify.InvalidArgumentError 'Request "precision" must be an integer'

	getRates (rates) ->
		if not from_rate = rates[from]
			return next new restify.InvalidArgumentError "Unknown currency code '#{from}'."

		if not to_rate = rates[to]
			return next new restify.InvalidArgumentError "Unknown currency code '#{to}'."

		converted_amount = (amount / from_rate) * to_rate
		converted_amount = parseFloat converted_amount.toFixed precision

		return next res.send {
			original:
				amount: amount,
				currency: from,
				rate: from_rate
			converted:
				amount: converted_amount
				currency: to
				rate: to_rate
			information:
				disclaimer: disclaimer,
				license: license,
				age: getRatesAge() + 's'
				expires: (ttl - getRatesAge()) + 's'
		}
