consul  = require('consul')()
events  = require 'events'
os      = require 'os'
sift    = require 'sift'

Systemd = require './systemd'
P       = require './promise-utils'

class Semaphore extends events.EventEmitter
  constructor: (@prefix, @limit) ->
    @modifyIndex = 0
    @acquireing = false
    @limit ?= 9999
    @readLock()

  readLock: () ->
    @lock = new Promise (resolve, reject) =>
      console.log 'read'

      consul.kv.get {key: "#{@prefix}/lock/.lock"}, (err, res) =>
        if err
          reject err
        if res?
          lock = JSON.parse "#{res.Value}"
          lock.ModifyIndex = res.ModifyIndex
          @limit = lock.Limit if lock.Limit?
          resolve lock
        else
          @updateLock {Limit: @limit, Holders: []}
          .then =>
            @lock.then (lock) =>
              resolve lock
  updateLock: (lock)->
    opts =
      key:   "#{@prefix}/lock/.lock"
      value: JSON.stringify lock, (k,v) -> v if k isnt "ModifyIndex"
    if lock.ModifyIndex
      opts.cas = lock.ModifyIndex
    console.log 'update'
    console.log lock
    console.log opts
    new Promise (resolve, reject) =>
      consul.kv.set opts, (err, res) =>
        @readLock()
        console.log 'updated'
        console.log res
        @lock.then (lock) =>
          if err or res == false
            reject err
          else
            resolve res
  setLimit: (limit) ->
    console.log 'setlimit'
    @limit = limit
    @lock.then (lock) =>
      if limit isnt lock.Limit
        console.log 'updatelimit'
        console.log limit
        lock.Limit limit
        updateLock lock
  acquire: (opts) ->
    return if @acquireing
    @acquireing = true
    tryAcquire = (waitChange)=>
      console.log 'try'

      getOpts = 
        key: "#{@prefix}/lock"
        recurse: true
      if waitChange
        getOpts.index = @modifyIndex
      console.log getOpts
      @lock.then (lock) =>
        console.log 'a'
        console.log lock
        consul.kv.get getOpts, (err, res) =>
          console.log 'b'
          return if not @acquireing
          keys = {}
          if res?
            for v in res
              @modifyIndex = v.ModifyIndex if v.ModifyIndex > @modifyIndex
              if v.Key is "#{@prefix}/lock/.lock"
                lock = JSON.parse "#{v.Value}"
                lock.ModifyIndex = v.ModifyIndex
                lock.Limit ?= @limit
              else if v.Session?
                keys[v.Session] = true
          console.log keys
          lock.Holders ?= []
          lock.Holders = lock.Holders.filter (id) -> keys[id]?
          console.log lock
          if lock.Holders.length >= lock.Limit
            console.log "no slot on #{@prefix} mod: #{@modifyIndex}"
            tryAcquire(true)
            return
          lock.Holders.push @session.ID
          @updateLock lock
          .then (lock) =>
            @emit 'acquired'
          .catch (err) =>
            console.log "race on #{@prefix} mod: #{@modifyIndex}"
            tryAcquire(true)

    if @session?
      tryAcquire()
    else
      consul.session.create @prefix, (err, @session) =>
        consul.kv.set {key: "#{@prefix}/lock/#{@session.ID}", value: @prefix, acquire: @session.ID}, (err, res) =>
          tryAcquire()

class Diplomat
  constructor: ->
    @services = {}

    update = (mod) =>
      getOpts = 
        key: "diplomat/services"
        recurse: true
      if mod?
        getOpts.index = mod
      console.log getOpts
      consul.kv.get getOpts, (err, res) =>
        mod = 0
        s = {}
        if res? 
          for v in res
            console.log v.Key
            continue unless v.Key.startsWith "diplomat/services/"
            mod = v.ModifyIndex if v.ModifyIndex > mod
            name = v.Key.substr "diplomat/services/".length
            console.log name
            if @services[name]?
              s[name] = @services[name]
            else
              s[name] = new Diplomat.Service name, v

        @services = s
        if res?
          update mod
        else
          setTimeout update, 5000
    update()

host =
  endianness: os.endianness()
  hostname:   os.hostname()
  type:       os.type()
  platform:   os.platform()
  arch:       os.arch()
  release:    os.release()
  uptime:     os.uptime()
  loadavg:    os.loadavg()
  totalmem:   os.totalmem()
  freemem:    os.freemem()
  cpus:       os.cpus()

class Diplomat.Service
  constructor: (@name, data) ->
    unit = new Systemd.Unit "#{@name}.service"
    semaphore = new Semaphore "service/#{@name}"
    console.log @name
    unit.on 'failed', (err) ->
      console.log 'fail'
      console.log err
      semaphore.release()
    unit.on 'stopped', () ->
      console.log "stopped"
    semaphore.on 'acquired', ->
      unit.start()
    semaphore.on 'released', ->
      unit.stop()

    update = (mod) ->
      getOpts = 
        key: "diplomat/services/#{@name}"
      if mod?
        getOpts.index = mod
      console.log getOpts
      consul.kv.get getOpts, (err, res) ->
        if err
          console.log err
        if res
          checkData JSON.parse "#{res.Value}"
          update res.ModifyIndex
    checkData = (data) ->
      console.log 'check'
      console.log data
      if data.match?
        check = sift data.match
      if not data.match? or check.test host
        semaphore.setLimit data.Limit
        semaphore.acquire()
      else
        semaphore.release()

    if data?
      checkData JSON.parse "#{data.Value}"
      update data.ModifyIndex
    else
      update()

new Diplomat()
