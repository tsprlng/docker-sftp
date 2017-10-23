# docker-sftp

Some people wanted a Dockerized SFTP server to use for integration testing.

Since the rest of the stuff in that environment is configured with YAML files, I thought I'd try and make the SFTP server image the same.

This project accomplishes that by the pleasantly hackish means of parsing the YAML file at startup, and setting up files in the container filesystem to match the config before starting the SSH server.


## Config

For an example config, see config.yml.example

It can either be bind-mounted in at `/config.yml`, the default location, or passed in as a secret in which case `/run/secrets/whatever` should be passed as the only argument to the process through the `run` command.

Users can have a password or one or more public keys, or both, or (very pointlessly) neither.

All users will get access to the same shared folder (the volume `/sftp/data`, which looks like `/data` to users). (This image is for a single-bucket server by design, and this will not change. Make your own if you want something else.)

You can specify any or all types of host key, or none, in which case they'll be generated randomly each time.


## Implementation

Since I was aiming to optimize for image size, using an interpreted language packaged with a ton of unused libraries and other crap was not acceptable. Alpine's Python for instance was 40MB.

I also wasn't in the mood to write C so this is done (rather messily) in Haskell, which made a nice change.

It's compiled from scratch with `--split-objs` enabled for all Stack dependencies, but sadly is compiled against glibc which then had to be statically linked, so it still comes out at about 3MB + openssh-server.

I'll try again later to compile it against musl from within Alpine -- this should result in a much smaller image. The config interface won't change though, as long as the built image is called `tsprlng/sftp:0`.
