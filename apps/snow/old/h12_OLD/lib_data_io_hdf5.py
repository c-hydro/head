"""
Library Features:

Name:          lib_data_io_hdf5
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20160708'
Version:       '1.5.0'
"""
#################################################################################
# Library
import logging

from lib_default_args import sLoggerName

# Logging
oLogStream = logging.getLogger(sLoggerName)
#################################################################################

# --------------------------------------------------------------------------------
# Method to open hdf5 file
def openFile(sFileName, sFileMode):
    import h5py

    try:
        # Open file
        oFile = h5py.File(sFileName, sFileMode)
        return oFile

    except IOError as oError:
        oLogStream.error(' -----> ERROR: in open file (lib_data_io_hdf5)' + ' [' + str(oError) + ']')
        raise RuntimeError('File open failed')

# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to close hdf5 file
def closeFile(oFile):
    oLogStream.warning(' -----> Warning: no close method defined (lib_data_io_hdf5)')
    pass

# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to get variable by name
def getVar(oFile, sVarName):
    oVarData = oFile[str(sVarName)].value
    return oVarData
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Method to get all variable(s) by file handle
def getVars(oFile, sDsetValueKey='values', sDsetAttrKey='parameters'):

    oFileDict = {}
    for sDataSet in oFile:

        oDataSet = oFile[sDataSet]
        oFileDict[sDataSet] = {}
        try:
            oFileDict[sDataSet][sDsetValueKey] = {}
            oFileDict[sDataSet][sDsetAttrKey] = {}
            oFileDict[sDataSet][sDsetValueKey] = oDataSet.value

            for oItem in oDataSet.attrs.keys():
                oValue = oDataSet.attrs[oItem]
                oFileDict[sDataSet][sDsetAttrKey][oItem] = {}
                oFileDict[sDataSet][sDsetAttrKey][oItem] = oValue

        except BaseException:
            oLogStream.warning(
                ' -----> Warning: impossible to get data values or attributes! Check your file! (lib_data_io_hdf5)')

    return oFileDict

# --------------------------------------------------------------------------------
