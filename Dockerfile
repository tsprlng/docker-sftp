FROM alpine:3.6

RUN apk add --update openssh-server \
	&& rm -rf /var/cache/apk/*

ADD ./config/.stack-work/install/x86_64-linux/lts-9.9/8.0.2/bin/config-exe /start

VOLUME ["/sftp/data"]
EXPOSE 22
ENTRYPOINT ["/start"]
CMD ["/config.yml"]
