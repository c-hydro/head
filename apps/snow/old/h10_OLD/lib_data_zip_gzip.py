"""
Library Features:

Name:          lib_data_zip_gzip
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20180521'
Version:       '2.0.7'
"""
#################################################################################
# Library
import logging
import gzip

from lib_default_args import sLoggerName

# Logging
oLogStream = logging.getLogger(sLoggerName)
#################################################################################

# --------------------------------------------------------------------------------
# Method to open zip file
def openZip(sFileName_IN, sFileName_OUT, sZipMode):
    # Check method
    try:

        # Open file
        if sZipMode == 'z':  # zip mode
            oFile_IN = open(sFileName_IN, 'rb')
            oFile_OUT = gzip.open(sFileName_OUT, 'wb')
        elif sZipMode == 'u':  # unzip mode
            oFile_IN = gzip.GzipFile(sFileName_IN, "rb")
            oFile_OUT = open(sFileName_OUT, "wb")

        # Pass file handle(s)
        return oFile_IN, oFile_OUT

    except IOError as oError:
        oLogStream.error(' =====> ERROR: in open file (GZip Zip)' + ' [' + str(oError) + ']')
        raise RuntimeError('Open file failed')
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to close zip file
def closeZip(oFile_IN=None, oFile_OUT=None):
    if oFile_IN:
        oFile_IN.close()
    if oFile_OUT:
        oFile_OUT.close()
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to zip file
def zipFile(oFile_IN=None, oFile_OUT=None):
    if oFile_IN and oFile_OUT:
        oFile_OUT.writelines(oFile_IN)
    else:
        oLogStream.error(' =====> ERROR: in zip file (GZip Zip)')
        raise RuntimeError('Zip file failed')
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to unzip file
def unzipFile(oFile_IN=None, oFile_OUT=None):
    if oFile_IN and oFile_OUT:
        oDecompressData = oFile_IN.read()
        oFile_OUT.write(oDecompressData)
    else:
        oLogStream.error(' =====> ERROR: in unzip file (GZip Zip)')
        raise RuntimeError('Unzip file failed')
# --------------------------------------------------------------------------------
