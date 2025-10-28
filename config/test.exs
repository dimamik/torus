import Config

config :req,
  default_options: [
    plug: {Req.Test, :req_plug}
  ]
