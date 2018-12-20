#!/bin/bash

set -e
set -x

MIN_PCT=1
MAX_PCT=99

PLATFORM=mac TEST_NAME=rails_10k erb single_csv_set.html.erb > mac_rails_10k.html

