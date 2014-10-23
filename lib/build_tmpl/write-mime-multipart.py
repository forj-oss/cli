#!/usr/bin/python

# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# largely taken from python examples
# http://docs.python.org/library/email-examples.html

import os
import sys


from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from optparse import OptionParser
import gzip

from base64 import b64encode

COMMASPACE = ', '

starts_with_mappings = {
    '#include': 'text/x-include-url',
    '#!': 'text/x-shellscript',
    '#cloud-config': 'text/cloud-config',
    '#upstart-job': 'text/upstart-job',
    '#part-handler': 'text/part-handler',
    '#cloud-boothook': 'text/cloud-boothook'
}


def get_type(fname, deftype):
    f = file(fname, "rb")
    line = f.readline()
    f.close()
    rtype = deftype
    for _str, mtype in starts_with_mappings.items():
        if line.startswith(_str):
            rtype = mtype
            break
    return rtype


def main():
    outer = MIMEMultipart()

    parser = OptionParser()

    parser.add_option("-o", "--output", dest="output",
                      help="write output to FILE [default %default]",
                      metavar="FILE", default="-")
    parser.add_option("-z", "--gzip", dest="compress", action="store_true",
                      help="compress output", default=False)
    parser.add_option("-d", "--default", dest="deftype",
                      help="default mime type [default %default]",
                      default="text/plain")
    parser.add_option("--delim", dest="delim",
                      help="delimiter [default %default]", default=":")
    parser.add_option("-b", "--base64", dest="base64", action="store_true",
                      help="encode content base64", default=False)

    (options, args) = parser.parse_args()

    if (len(args)) < 1:
        parser.error("Must give file list see '--help'")

    for arg in args:
        t = arg.split(options.delim, 1)
        path = t[0]
        if len(t) > 1:
            mtype = t[1]
        else:
            mtype = get_type(path, options.deftype)

        maintype, subtype = mtype.split('/', 1)
        if maintype == 'text':
            fp = open(path)
            # Note: we should handle calculating the charset
            msg = MIMEText(fp.read(), _subtype=subtype)
            fp.close()
        else:
            fp = open(path, 'rb')
            msg = MIMEBase(maintype, subtype)
            msg.set_payload(fp.read())
            fp.close()
            # Encode the payload using Base64
            encoders.encode_base64(msg)

        # Set the filename parameter
        msg.add_header('Content-Disposition', 'attachment',
                       filename=os.path.basename(path))

        outer.attach(msg)

    if options.output is "-":
        ofile = sys.stdout
    else:
        ofile = file(options.output, "wb")

    if options.base64:
        output = b64encode(outer.as_string())
    else:
        output = outer.as_string()

    if options.compress:
        gfile = gzip.GzipFile(fileobj=ofile, filename=options.output)
        gfile.write(output)
        gfile.close()
    else:
        ofile.write(output)

    ofile.close()

if __name__ == '__main__':
    main()