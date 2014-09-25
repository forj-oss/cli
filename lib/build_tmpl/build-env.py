#!/bin/env python
#
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

# This script is used to create a env file used by build.sh.
# It is based on Maestro/templates/infra/maestro.box.GITBRANCH.env.tmpl

# This script detects few tags, and ask to enter the appropriate vallue, 
# then save the result to a directory given by the user.

# As this script is very early in the boot process, we are running on end user worstation.
# We will avoid adding non default module like:
# - ptemplates, django for template interpreter. We use our own simple code to make it work with basics rules.
#   It provides variable detection, with comments and default variables.

import sys 
import getopt
#import urllib2
#from urlparse import urlparse,ParseResult
import re
import logging
import logging.handlers
import yaml
import os
#import subprocess
#import distutils.spawn
#import string 
#from datetime import date,datetime
#import time
#import tempfile
import readline

# Defining defaults

GITBRANCH='master'
MAESTRO_RPATH_TMPL="templates/infra/"
MAESTRO_TMPL_FILE="maestro.box.GITBRANCH.env.tmpl"
MAESTRO_TMPL_PROVIDER='hpcloud'

# 
# 
   
##############################
def help(sMsg):
   print 'build-env.py [-h|--help] --maestro-repo MaestroPath --env-path BuildEnvPath [--gitbranch BranchName] [-d|--debug] [-v|--verbose]'

# TODO Support for re-build it.

##############################
# TODO: split this function in 3, for code readibility

def BuildEnv(EnvPath, MaestroFile, MaestroPath, GitBranch):
  """Build env file if doesn't exist."""

  global MAESTRO_TMPL_FILE
  oLogging=logging.getLogger('build-env')

  # -----------------------------------------------
  # Check step ------------------------------------

  if not os.path.exists(EnvPath):
     oLogging.error("'%s' do not exist. This directory is required. (--env-path)", EnvPath)
     sys.exit(1)

  if not os.path.isdir(EnvPath):
     oLogging.error("'%s' is not a valid directory (--env_path)", EnvPath)
     sys.exit(1)

  if not os.path.isdir(MaestroPath):
     oLogging.error("'%s' is not a valid directory. Should refer to Maestro repository root dir.(--maestro-path)", MaestroPath)
     sys.exit(1)
     

  sInputFile=os.path.join(MaestroPath, MaestroFile)
  if not os.path.exists(sInputFile):
     oLogging.error("Unable to find template '%s' from '%s'. Are you sure about Maestro Repository root path given? Check and retry.", MaestroPath, MaestroFile)
     sys.exit(1)

  # Replace GITBRANCH Name by real git branch value.
  sOutputFile=os.path.join(EnvPath,re.sub('GITBRANCH',GITBRANCH,MAESTRO_TMPL_FILE))
  sOutputFile=re.sub('.tmpl$','',sOutputFile)
  
  if os.path.exists(sOutputFile):
     # TODO Support for re-build it.
     oLogging.info("'%s' exists. If you want to rewrite it, remove the file before.", sOutputFile)
     sys.exit(0)
  
  # Load template variables and build list of variable to query
  oLogging.debug("Opening template '%s'",sInputFile)
  try:
    fTmpl=open(sInputFile)
  except IOError as e:
    oLogging.error("Unable to open '%s'. Errno: %s (%s)", sInputFile, e.errno, e.strerror)
    sys.exit(2)
  
  # -----------------------------------------------
  # Reading template ------------------------------

  print("Reading template '{0}'".format(sInputFile))
  oComments={}
  oVars={}

  # Search for Variable. If the variable name ends with '!', this value could not be null.
  reVar=re.compile('[^$]{([A-Z_-]+)(!)?(:.*?)?}')
  # 1: Variable Name
  # 2: Required if = '!' 
  # 3: Default


  # Search for comment
  reComment=re.compile('^ *# +([A-Z_-]+): (.*)$')

  for line in fTmpl:

      # Detecting comment
      oComment=reComment.search(line)
      if oComment <> None:
         oLogging.debug('Found "%s" = "%s"', oComment.group(1), oComment.group(2))
         if oVars.has_key(oComment.group(1)):
            oComments[oComment.group(1)]=oVars[oVar.group(1)]['comments']+'\n# '+oComment.group(2)
         elif oComments.has_key(oComment.group(1)):
            oComments[oComment.group(1)]=oComments[oComment.group(1)]+'\n# '+ oComment.group(2)
         else:
            oComments[oComment.group(1)]='# '+oComment.group(2)

      oVar=reVar.search(line)   
      if oVar <> None:
         oLogging.debug('Found var "%s" from "%s"',oVar.group(1),line)

         sComment=''
         if oComments.has_key(oVar.group(1)):
            sComment=oComments[oVar.group(1)]
         else:
            oComments.remove(oVar.group(1))

         sDefault=''
         bRequired=False
         if oVar.group(2) <> None  :
            bRequired=True
            oLogging.debug("'%s' is required",oVar.group(1))
         if oVar.group(3) <> None:
            sDefault=oVar.group(3)[1:]
            oLogging.debug("'%s' default value is '%s'",oVar.group(1),sDefault)
            

         oVars[oVar.group(1)]={ 'comments': sComment,
                                'required': bRequired,
                                'default': sDefault } 

  oLogging.debug('template loaded.')

  # -----------------------------------------------
  # Ask section -----------------------------------

  print "We need some information from you. Please ask the following question:\n"
  # Time to ask information to the user.

  for sElem in oVars:
     print '{0}'.format(oVars[sElem]['comments'])
     sPar="# "
     if oVars[sElem]['default'] <> '':
        sPar+='Default is "'+oVars[sElem]['default']+'".'
     if oVars[sElem]['required'] :
        if sPar <> "# " :
           sPar+=' Required.'
        else:
           sPar='# Required.'

     if sPar <> "":
        print sPar
     sValue=""

     while sValue == "":
       sValue=raw_input(sElem+'=')

       if sValue == "":
          sValue=oVars[sElem]['default']
       
       if oVars[sElem]['required']:
          if sValue == "":
             print "[1mValue required[0m. Please enter a value.[2A[K"
       else:
          break

     oVars[sElem]['value']=sValue
     print '[A{0}="[1m{1}[0m"\n[K'.format(sElem,sValue)


  fTmpl.seek(0) # Read the file again to replace data
  try:
     fOutputFile=open(sOutputFile,"w+")
  except IOError as e:
    oLogging.error("Unable to open '%s' for write. Errno: %s (%s)", sOutputFile, e.errno, e.strerror)
    sys.exit(2)

  print "--------------------------------\nThank you\nWriting '{0}'".format(sOutputFile)

  # -----------------------------------------------
  # Time to save the template. --------------------
  
  reReplaced=re.compile('([^$])({([A-Z_-]+)(!)?(:.*?)?})')
  for line in fTmpl:
     oVar=reReplaced.search(line)

     if oVar <> None:
    
        if oVar.group(1) <> None:
           sValue=oVar.group(1)+oVars[oVar.group(3)]['value']
        else:
           sValue=oVars[oVar.group(3)]['value']
        sNewLine=reReplaced.sub(sValue,line)
     else:
        sNewLine=line

     sys.stdout.flush()
     fOutputFile.write(sNewLine)
  
  fOutputFile.close()
  fTmpl.close()
  print 'Done'



##############################
def main(argv):
  """Main function"""

  global GITBRANCH
  global MAESTRO_TMPL_PROVIDER
  global MAESTRO_RPATH_TMPL

  oLogging=logging.getLogger('build-env')
  oLogging.setLevel(20)

  try:
     opts,args = getopt.getopt(argv,"hp:vd:r:P:", ["help", "--for-provider=", "env-path=" , "maestro-path=" ,"debug" ,"verbose" ])
  except getopt.GetoptError, e:
     oLogging.error('Error: '+e.msg)
     help()
     sys.exit(2)

  for opt, arg in opts:
     if opt in ('-h', '--help'):
        help()
        sys.exit()
     elif opt in ('-v','--verbose'):
        if oLogging.level >20:
           oLogging.setLevel(oLogging.level-10)
     elif opt in ('--debug','-d'):
        logging.getLogger().setLevel(logging.DEBUG)
        logging.debug("Setting debug mode")
        oLogging.setLevel(logging.DEBUG)
     elif opt in ('-p', '--env-path'):
        ENV_PATH=arg
     elif opt in ('--gitbranch'):
        GITBRANCH=arg
     elif opt in ('-r','--maestro-path'):
        MAESTRO_PATH=arg
     elif opt in ('-P','--for-provider'):
        TMPL_PROVIDER=arg

  # Start Main tasks - Testing required variables.
  if not 'ENV_PATH' in locals() or not 'MAESTRO_PATH' in locals():
     oLogging.error("--env-path or --maestro-path values missing. Please check command flags.")
     sys.exit(1)


  global MAESTRO_TMPL_FILE # template file to use.
  
  sMaestroFile=os.path.join(MAESTRO_RPATH_TMPL, MAESTRO_TMPL_PROVIDER+'-'+MAESTRO_TMPL_FILE)
  BuildEnv(ENV_PATH, sMaestroFile, MAESTRO_PATH, GITBRANCH)

  sys.exit(0)

#####################################
logging.basicConfig(format='%(asctime)s: %(levelname)s - %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p')

if __name__ == "__main__":
   main(sys.argv[1:])


