#!/usr/bin/env python3

import argparse
import yaml
import re
import sys

lpid = r"([~a-z0-9\-]+/)?"
charm = r"([a-z0-9\-]+)"
charm_match = re.compile(r".*cs:{}{}-([0-9]+)\s*$".format(lpid, charm))


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "FILE",
        help="Parse bundle from FILE. If specifying `-` then read "
        "from standard input.",)
    parser.add_argument(
        "--get-charms",
        action="store_true",
        help="Get charms and their revisions from bundle.")
    return parser.parse_args()


def get_charms(bundle):
    charms = {}
    for app in bundle['applications']:
        charms[app] = bundle['applications'][app]['charm']
    return charms


def process(bundle_file, options):
    versions_found = False
    bundle = yaml.load(bundle_file, Loader=yaml.SafeLoader)
    if options.get_charms:
        charms = get_charms(bundle)
        for app in charms:
            ret = charm_match.match(charms[app])
            if ret:
                versions_found = True
                _charm = ret.group(2)
                if ret.group(1):
                    _charm = "{}{}".format(ret.group(1), _charm)

                print(_charm, charms[app])

    if not versions_found:
        sys.stderr.write("WARNING: no valid charm revisions found in {}\n\n".
                         format(bundle_file.name))


def main():
    options = parse_arguments()
    if options.FILE == "-":
        with sys.stdin as bundle:
            process(bundle, options)
    else:
        with open(options.FILE) as bundle:
            process(bundle, options)


if __name__ == "__main__":
    main()