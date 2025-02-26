"""
Library Features:

Name:          lib_utils_io_nc
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230727'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging
import os
import numpy as np
import pandas as pd
import xarray as xr
import h5py

from copy import deepcopy

from lib_info_args import logger_name
from lib_utils_io import create_darray

# set logger
alg_logger = logging.getLogger(logger_name)

# debug
import matplotlib.pylab as plt

# default netcdf encoded attributes
attrs_encoded = ["_FillValue", "dtype", "scale_factor", "add_offset", "grid_mapping"]
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to organize nc file
def organize_file_nc(obj_variable, obj_time=None, obj_geo_x=None, obj_geo_y=None,
                     obj_var_name=None,
                     var_name_time='time', var_name_geo_x='longitude', var_name_geo_y='latitude',
                     coord_name_time='time', coord_name_x='longitude', coord_name_y='latitude',
                     dim_name_time='time', dim_name_x='longitude', dim_name_y='latitude'):

    # organize variable name(s)
    if obj_var_name is None:
        obj_var_name = {}

    # organize time information
    var_data_time = None
    if obj_time is not None:
        if isinstance(obj_time, str):
            var_data_time = pd.DatetimeIndex([pd.Timestamp(obj_time)])
        elif isinstance(obj_time, pd.DatetimeIndex):
            var_data_time = deepcopy(obj_time)
        elif isinstance(obj_time, pd.Timestamp):
            var_data_time = pd.DatetimeIndex([obj_time])
        else:
            alg_logger.error(' ===> Time obj format is not supported')
            raise NotImplemented('Case not implemented yet')

    # organize geo information
    var_geo_x_1d = np.unique(obj_geo_x.flatten())
    var_geo_y_1d = np.unique(obj_geo_y.flatten())

    # iterate over variable(s)
    variable_dset = xr.Dataset()
    for variable_name, variable_data in obj_variable.items():

        if variable_name in list(obj_var_name.keys()):
            variable_name = obj_var_name[variable_name]

        variable_da = create_darray(
            variable_data, obj_geo_x, obj_geo_y,
            geo_1d=True, time=var_data_time,
            coord_name_x=coord_name_x, coord_name_y=coord_name_y, coord_name_time=coord_name_time,
            dim_name_x=dim_name_x, dim_name_y=dim_name_y, dim_name_time=dim_name_time)

        variable_dset[variable_name] = variable_da.copy()

    return variable_dset
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to read nc file
def read_file_nc(file_name, file_variables=None, var_name_geo_x='longitude', var_name_geo_y='latitude'):

    # check file availability
    if os.path.exists(file_name):

        # open file
        try:
            file_dset = xr.open_dataset(file_name)
        except BaseException as b_exp:
            alg_logger.warning(' ===> File "' + file_name + '" errors in opening file "' +
                               str(b_exp) + '". Return NoneType')
            data_obj, geo_obj = None, None
            return data_obj, geo_obj

        # check coords
        tmp_geo_x_1d = file_dset['lon'].values
        tmp_geo_y_1d = file_dset['lat'].values

        tmp_geo_x_max = np.nanmax(tmp_geo_x_1d)
        if tmp_geo_x_max > 180:
            file_dset.coords['lon'] = (file_dset.coords['lon'] + 180) % 360 - 180
            file_dset = file_dset.sortby(file_dset['lon'])

            file_dset.coords['lon'] = tmp_geo_x_1d - 180

        # organize file obj
        data_obj, geo_obj, geo_dims = {}, {}, None
        for var_name_out, var_name_in in file_variables.items():
            if var_name_out == var_name_geo_x:
                geo_obj[var_name_out] = file_dset[var_name_in].values
                if geo_dims is None:
                    geo_dims = file_dset[var_name_in].ndim
            if var_name_out == var_name_geo_y:
                geo_obj[var_name_out] = file_dset[var_name_in].values
                if geo_dims is None:
                    geo_dims = file_dset[var_name_in].ndim

            if var_name_in != var_name_geo_x or var_name_in != var_name_geo_y:
                if var_name_in in list(file_dset.data_vars):
                    tmp_values = file_dset[var_name_in].values
                    data_values = np.squeeze(tmp_values)

                    ''' debug
                    plt.figure()
                    plt.imshow(data_values)
                    plt.colorbar()
                    plt.show()
                    '''

                    data_obj[var_name_out] = data_values
                else:
                    if var_name_in not in [var_name_geo_x, var_name_geo_y]:
                        alg_logger.warning(' ===> Variable "' + var_name_in + '" not found in the dataset')

    else:
        alg_logger.warning(' ===> File name "' + file_name + '" not found')
        data_obj, geo_obj, geo_dims = None, None, None

    # check geo dimensions and data
    if geo_dims is not None:
        if geo_dims == 1:
            geo_x_arr, geo_y_arr = geo_obj[var_name_geo_x], geo_obj[var_name_geo_y]
            geo_x_grid, geo_y_grid = np.meshgrid(geo_x_arr, geo_y_arr)
            geo_obj[var_name_geo_x], geo_obj[var_name_geo_y] = geo_x_grid, geo_y_grid

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
