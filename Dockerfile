FROM debian:buster

RUN apt-get update && apt-get install curl html2text netcat-openbsd
RUN pip install jinja2-cli
