#!/usr/bin/env bash
# {#
# this part of the script will be a comment for jinja, until the closing mark below

# Usage: ./import-covid-austria.sh | netcat -q 1 influxdb 4242
# will download covid19 data of austria from different sources,
# combine and transform this data into opentdsb telnet format,
# ready to be imported into a timeseries database.
# currently most data comes from corin.at,
# additional data is scraped from the sozialministerium website

set -eo pipefail
self=$(readlink -e "$0")

for i in curl html2text jinja2; do if ! which $i > /dev/null; then
    echo "error, missing command $i; try 'apt-get install curl html2text; pip install jinja2-cli'"
    exit 1
fi; done

# update json structure [{'dataTime':'isoformat'},] with [{'timestamp':'unixepoch'},]
json_dataTime2timestamp="
import sys, json, datetime;
src_data = json.load(sys.stdin);
data = [{ **item, 'timestamp': int(datetime.datetime.fromisoformat(item['dataTime']).timestamp()) } for item in src_data];
json.dump(data, sys.stdout, sort_keys=True, indent=0)
"

bmsgpk=$(curl -s "https://corin.at/data.php?format=json" | \
    python3 -c "$json_dataTime2timestamp")
ems=$(curl -s "https://corin.at/data_ems.php?format=json" | \
    python3 -c "$json_dataTime2timestamp")
sminfo_raw=$(curl -s "https://www.sozialministerium.at/Informationen-zum-Coronavirus/Neuartiges-Coronavirus-(2019-nCov).html" | \
    html2text -utf8 -width 200  | grep "Zahlen aus Österreich" -A 14)
extract_timestamp="s/.+Stand +([0-9]+).([0-9]+).([0-9]+)[^0-9]+([0-9]+:[0-9]+).+Uhr.*/\3-\2-\1T\4:00/g"
extract_value="s/.+ +([0-9.]+) *$/\1/g"
smdeath_timestamp=$(date --date=$(printf "%s" "${sminfo_raw}" | \
    grep "^Todesfälle" -A 1 | grep Stand | sed -r "$extract_timestamp") +%s)
smhospital_timestamp=$(date --date=$(printf "%s" "${sminfo_raw}" | \
    grep "^Hospitalisierung" -A 1 | grep Stand | sed -r "$extract_timestamp") +%s)
smintensive_timestamp=$(date --date=$(printf "%s" "${sminfo_raw}" | \
    grep "^Intensivstation" -A 1 | grep Stand | sed -r "$extract_timestamp") +%s)
smrecovered_timestamp=$(date --date=$(printf "%s" "${sminfo_raw}" | \
    grep "^Genesen" -A 1 | grep Stand | sed -r "$extract_timestamp") +%s)
smtests_timestamp=$(date --date=$(printf "%s" "${sminfo_raw}" | \
    grep "^Testungen" -A 1 | grep Stand | sed -r "$extract_timestamp") +%s)
smdeath=$(printf "%s" "${sminfo_raw}" | grep "^Todesfälle" | \
    sed -r "$extract_value" | tr -d ".")
smhospital=$(printf "%s" "${sminfo_raw}" | grep "^Hospitalisierung" | \
    sed -r "$extract_value" | tr -d ".")
smintensive=$(printf "%s" "${sminfo_raw}" | grep "^Intensivstation" | \
    sed -r "$extract_value" | tr -d ".")
smrecovered=$(printf "%s" "${sminfo_raw}" | grep "^Genesen" | \
    sed -r "$extract_value" | tr -d ".")
smtests=$(printf "%s" "${sminfo_raw}" | grep "^Testungen" | \
    sed -r "$extract_value" | tr -d ".")
sminfo="[
    {\"timestamp\": \"${smdeath_timestamp}\", \"death\": \"${smdeath}\"},
    {\"timestamp\": \"${smhospital_timestamp}\", \"hospital\": \"${smhospital}\"},
    {\"timestamp\": \"${smintensive_timestamp}\", \"intensive\": \"${smintensive}\"},
    {\"timestamp\": \"${smrecovered_timestamp}\", \"recovered\": \"${smrecovered}\"},
    {\"timestamp\": \"${smtests_timestamp}\", \"tests\": \"${smtests}\"}
]"

# use the script as jinja template by hiding the bash part from jinja
printf '{ "BMSGPK":\n%s,\n"EMS":\n%s,\n"SMINFO":\n%s\n}' "$bmsgpk" "$ems" "${sminfo}" | \
    jinja2 --strict -D country=Austria --format json $self /dev/stdin | \
    tail -n +3
exit 0

# everything until here is ignored by jinja; all following "exit 0" is not parsed by bash
# #}
{%- set bmsgpk_list= [
    ('confirmed', 'confirmed'), ('deltatimehrs', 'deltaTimeHrs'),
    ('recovered', 'recovered'), ('new', 'new'), ('newtests', 'newTests'),
    ('deltatimehrs', 'deltaTimeHrs'), ('growth', 'growth'),
    ('growth24', 'growth24'),
    ] %}
{%- set ems_list= [('ill', 'erkr'),] %}
{%- set sm_list= [
    ('death', 'death'), ('hospital', 'hospital'), ('intensive', 'intensive'),
    ('tests', 'tests')] %}
{%- for item in BMSGPK %}
    {%- for graphname,orgname in bmsgpk_list %}
        {%- if item[orgname]|d(0) %}
put covid19_{{ graphname }}  {{ item.timestamp|string }}  {{ item[orgname] }} country={{ country }} __name__=covid19_{{ graphname }}
        {%- endif %}
    {%- endfor %}
{%- endfor %}
{%- for item in EMS %}
    {%- for graphname,orgname in ems_list %}
        {%- if item[orgname]|d(0) %}
put covid19_{{ graphname }}  {{ item.timestamp|string }}  {{ item[orgname] }} country={{ country }} __name__=covid19_{{ graphname }}
        {%- endif %}
    {%- endfor %}
{%- endfor %}
{%- for item in SMINFO %}
    {%- for graphname,orgname in sm_list %}
        {%- if item[orgname]|d(0) %}
put covid19_{{ graphname }}  {{ item.timestamp|string }}  {{ item[orgname] }} country={{ country }} __name__=covid19_{{ graphname }}
        {%- endif %}
    {%- endfor %}
{%- endfor %}
