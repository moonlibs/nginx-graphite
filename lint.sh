#!/bin/bash

luacheck app/** --formatter TAP --ignore 143 --ignore 631 --ignore 61[14] --ignore 542 --ignore 41[12] --ignore 43[12] --ignore 211 --ignore 512 --ignore 122 --ignore 311 --codes | grep not\ ok
