"""
Library Features:

Name:          lib_data_io_hdf5
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230727'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging
import os
import h5py
import xarray as xr

from copy import deepcopy

from lib_info_args import logger_name
from lib_utils_generic import search_key_by_value

# set logger
alg_logger = logging.getLogger(logger_name)

# default netcdf encoded attributes
attrs_encoded = ["_FillValue", "dtype", "scale_factor", "add_offset", "grid_mapping"]
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to read hdf5 file
def read_file_hdf5(file_name, file_variables=None,
                   var_name_geo_x='longitude', var_name_geo_y='latitude'):

    # check file availability
    if os.path.exists(file_name):

        # open file
        file_dset = h5py.File(file_name, 'r')

        data_obj, geo_obj = {}, {}
        for var_name_in in file_dset:

            # find variable name
            var_name_out = None
            if file_variables is not None:
                if var_name_in in list(file_variables.values()):
                    var_name_out = search_key_by_value(file_variables, var_name_in)[0]

            # check variable availability
            if var_name_out is not None:

                # get data
                var_obj = file_dset[var_name_in]
                var_values = var_obj[:]

                # store data
                if var_name_out == var_name_geo_x:
                    geo_obj[var_name_out] = {}
                    geo_obj[var_name_out] = var_values
                elif var_name_out == var_name_geo_y:
                    geo_obj[var_name_out] = {}
                    geo_obj[var_name_out] = var_values
                else:
                    data_obj[var_name_out] = {}
                    data_obj[var_name_out] = var_values

        return data_obj, geo_obj

# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to write nc file
def write_file_nc(file_name, dset_data,
                  dset_mode='w', dset_engine='netcdf4', dset_compression=9, dset_format='NETCDF4',
                  dim_key_time='time', no_data=-9999.0):

    dset_encoded = dict(zlib=True, complevel=dset_compression)

    dset_encoding = {}
    for var_name in dset_data.data_vars:

        if isinstance(var_name, bytes):
            tmp_name = var_name.decode("utf-8")
            dset_data.rename({var_name: tmp_name})
            var_name = deepcopy(tmp_name)

        var_data = dset_data[var_name]
        if len(var_data.dims) > 0:
            dset_encoding[var_name] = deepcopy(dset_encoded)

        var_attrs = dset_data[var_name].attrs
        if var_attrs:
            for attr_key, attr_value in var_attrs.items():
                if attr_key in attrs_encoded:

                    dset_encoding[var_name][attr_key] = {}

                    if isinstance(attr_value, list):
                        attr_string = [str(value) for value in attr_value]
                        attr_value = ','.join(attr_string)

                    dset_encoding[var_name][attr_key] = attr_value

        if '_FillValue' not in list(dset_encoding[var_name].keys()):
            dset_encoding[var_name]['_FillValue'] = no_data

    if dim_key_time in list(dset_data.coords):
        dset_encoding[dim_key_time] = {'calendar': 'gregorian'}

    dset_data.to_netcdf(path=file_name, format=dset_format, mode=dset_mode,
                        engine=dset_engine, encoding=dset_encoding)
# ----------------------------------------------------------------------------------------------------------------------
