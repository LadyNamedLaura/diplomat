dbus   = require 'dbus-native'
events = require 'events'
P      = require './promise-utils'

bus = dbus.systemBus()

Systemd =
  bus: bus.getService('org.freedesktop.systemd1');
Systemd.manager = new Promise (resolve, reject) ->
  Systemd.bus.getInterface '/org/freedesktop/systemd1', 'org.freedesktop.systemd1.Manager', P.cb resolve, reject


class Systemd.Unit extends events.EventEmitter
  constructor: (@name) ->
    unitname = new P Systemd.manager, (manager, resolve, reject) =>
      manager.LoadUnit @name, P.cb resolve, reject

    @unit = new P unitname, (name, resolve, reject) ->
      Systemd.bus.getInterface name, 'org.freedesktop.systemd1.Unit', P.cb resolve, reject
    @properties = new P unitname, (name, resolve, reject) ->
      Systemd.bus.getInterface name, 'org.freedesktop.DBus.Properties', P.cb resolve, reject
    @properties.then (p) =>
      p.on 'PropertiesChanged', (err, res) =>
        console.log 'p' 
        for i in res
          name = i[0]
          v = i[1][1][0]
          if name is 'ActiveState'
            console.log v
            @emit v
          else if name is 'SubState'
            console.log 'substate'
            console.log v
    unitname.then (u) ->
      console.log u
    unitname.catch (err) =>
      @emit 'failed', err

  start: (mode = 'replace') ->
    @unit.then (unit) =>
      unit.Start mode, (err, res) =>
        console.log res
        console.log err

  stop: (mode = 'replace') ->
    @unit.then (unit) =>
      unit.Stop mode, (err, res) =>
        console.log res
        console.log err

module.exports = Systemd