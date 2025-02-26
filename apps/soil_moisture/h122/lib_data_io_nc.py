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
def read_file_nc(file_name, file_variables=None, file_time_reference=None,
                 var_name_geo_x='longitude', var_name_geo_y='latitude',
                 var_name_obs='obs',
                 var_time_creation='date_created_utc',
                 var_time_sensing_start='sensing_start_time_utc', var_time_sensing_end='sensing_end_time_utc'):

    # check file availability
    if os.path.exists(file_name):

        # check file time reference format
        if not isinstance(file_time_reference, pd.Timestamp):
            file_time_reference = pd.Timestamp(file_time_reference)

        # open file
        try:
            file_dset = xr.open_dataset(file_name)
        except BaseException as b_exp:
            alg_logger.warning(' ===> File "' + file_name + '" errors in opening file "' +
                               str(b_exp) + '". Return NoneType')
            data_obj, attrs_obj, geo_obj, time_obj = None, None, None, None
            return data_obj, attrs_obj, geo_obj, time_obj

        file_n_obs = file_dset.coords[var_name_obs].shape[0]

        # organize attrs obj
        attrs_obj = file_dset.attrs

        # organize time object
        time_creation, time_sensing_start, time_sensing_end = None, None, None
        if var_time_creation in list(attrs_obj):
            time_creation = attrs_obj[var_time_creation]
        if var_time_sensing_start in list(attrs_obj):
            time_sensing_start = attrs_obj[var_time_sensing_start]
        if var_time_sensing_end in list(attrs_obj):
            time_sensing_end = attrs_obj[var_time_sensing_end]

        time_obj = {'time_creation': time_creation,
                    'time_sensing_start': time_sensing_start, 'time_sensing_end': time_sensing_end}

        # organize data and geo object(s)
        data_obj, geo_obj = {}, {}
        for var_name_out, var_name_in in file_variables.items():
            if var_name_out == var_name_geo_x:
                geo_obj[var_name_out] = file_dset[var_name_in].values
            if var_name_out == var_name_geo_y:
                geo_obj[var_name_out] = file_dset[var_name_in].values

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

        # add time creation
        time_creation_arr = [pd.Timestamp(time_creation)] * file_n_obs
        data_obj['ssm_time_creation'] = time_creation_arr

        # add time difference
        time_delta_difference = file_time_reference - pd.Timestamp(time_creation)
        time_hours_difference = int(np.round(time_delta_difference.total_seconds() / 3600))
        time_difference_arr = np.zeros(file_n_obs)
        time_difference_arr[:] = time_hours_difference
        data_obj['ssm_time_difference'] = time_difference_arr

    else:
        alg_logger.warning(' ===> File name "' + file_name + '" not found')
        data_obj, attrs_obj, geo_obj, time_obj = None, None, None, None

    return data_obj, attrs_obj, geo_obj, time_obj

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
