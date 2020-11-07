FROM debian:buster

RUN apt-get update && apt-get install curl html2text netcat-openbsd
RUN pip install jinja2-cli

CMD script or cron or something that calls once a day at 14:30 \
      import-covid19-austria.sh | nc -q 1 influxdb 4242
