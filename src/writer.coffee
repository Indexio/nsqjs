Debug = require 'debug'
{EventEmitter} = require 'events'

_ = require 'underscore'
{ConnectionConfig} = require './config'
{WriterNSQDConnection} = require './nsqdconnection'

###
Publish messages to nsqds.

Usage:

w = new Writer '127.0.0.1', 4150
w.connect()

w.on Writer.READY, ->
  # Send a single message
  w.publish 'sample_topic', 'one'
  # Send multiple messages
  w.publish 'sample_topic', ['two', 'three']
w.on Writer.CLOSED, ->
  console.log 'Writer closed'
###
class Writer extends EventEmitter

  # Writer events
  @READY: 'ready'
  @CLOSED: 'closed'
  @ERROR: 'error'

  constructor: (@nsqdHost, @nsqdPort, options) ->
    super
    # Handy in the event that there are tons of publish calls
    # while the Writer is connecting.
    @setMaxListeners 10000

    @debug = Debug "nsqjs:writer:#{@nsqdHost}/#{@nsqdPort}"
    @config = new ConnectionConfig options
    @config.validate()
    @ready = false

    @debug 'Configuration'
    @debug @config

  connect: ->
    @conn = new WriterNSQDConnection @nsqdHost, @nsqdPort, @config
    @debug 'connect'
    @conn.connect()

    @conn.on WriterNSQDConnection.READY, =>
      @debug 'ready'
      @emit Writer.READY

    @conn.on WriterNSQDConnection.CLOSED, =>
      @debug 'closed'
      @emit Writer.CLOSED

    @conn.on WriterNSQDConnection.ERROR, (err) =>
      @debug 'error', err
      @emit Writer.ERROR, err

    @conn.on WriterNSQDConnection.CONNECTION_ERROR, (err) =>
      @debug 'error', err
      @emit Writer.ERROR, err

    @on Writer.READY, =>
      @ready = true

    @on Writer.ERROR, =>
      @ready = false

    @on Writer.CLOSED, =>
      @ready = false

  ###
  Publish a message or a list of messages to the connected nsqd. The contents
  of the messages should either be strings or buffers with the payload encoded.

  Arguments:
    topic: A valid nsqd topic.
    msgs: A string, a buffer, a JSON serializable object, or
      a list of string / buffers / JSON serializable objects.
  ###
  publish: (topic, msgs, callback) ->
    connState = @conn?.connectionState()?.current_state_name

    if not @conn or connState in ['CLOSED', 'ERROR']
      err = new Error 'No active Writer connection to send messages'

    if not msgs or _.isEmpty msgs
      err = new Error 'Attempting to publish an empty message'

    if err
      return callback err if callback
      throw err

    # TODO: Add CONNECTING event.

    # Call publish again once the Writer is ready.
    unless @ready
      @on Writer.READY, (err) =>
        return callback err if err
        @publish topic, msgs, callback
      return

    msgs = [msgs] unless _.isArray msgs

    # Automatically serialize as JSON if the message isn't a String or a Buffer
    msgs = for msg in msgs
      if _.isString(msg) or Buffer.isBuffer(msg)
        msg
      else
        JSON.stringify msg

    @conn.produceMessages topic, msgs, callback

  close: ->
    @conn.destroy()

module.exports = Writer
