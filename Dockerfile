FROM ruby:2.4

ENV DEBIAN_FRONTEND noninteractive

# Install samba
RUN apt-get -qq update && \
    apt-get install -y bash samba samba-client

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY . /usr/src/app
RUN bundle install
