P = (deps..., cb) ->
  new Promise (res, rej) ->
    Promise.all(deps).then (depvals) ->
      cb depvals..., res, rej

P.cb = (resolve, reject) ->
  (err, res) ->
    if err
      reject err
    else
      resolve res

P.wrap = (func, a...) ->
  new Promise (res, rej) ->
    func a..., (err, res) ->
      console.log 'oh'
      if err
        reject err
      else
        resolve res

module.exports = P