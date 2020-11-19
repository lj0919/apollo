#!/usr/bin/env python
import os
import yaml
import argparse


def list_files(dir_path):
    """List all sub-files in given dir_path."""
    return [
        os.path.join(root, f) for root, _, files in os.walk(dir_path)
        for f in files
    ]


def getInputDirDataSize(path):
    sumsize = 0
    filelist = list_files(path)
    for file in filelist:
        size = os.path.getsize(file)
        sumsize += size
    return int(sumsize)


def missing_config_file(path):
    sample_config_files = []
    for (dirpath, _, filenames) in os.walk(path):
        for filename in filenames:
            if filename == 'sample_config.yaml':
                end_file = os.path.join(dirpath, filename)
                sample_config_files.append(end_file)
    if (len(sample_config_files) == 0):
        return True, []
    return False, sample_config_files


def missing_calibration_task(sample_config_files):
    for sample_config_file in sample_config_files:
        print(sample_config_file)
        with open(sample_config_file, 'r') as f:
            data = yaml.safe_load(f)
        if not ('calibration_task' in data):
            return True
    return False


def file_type_exist(file_dir, file_type):
    files = os.listdir(file_dir)

    for k in range(len(files)):
        files[k] = os.path.splitext(files[k])[1]
    if file_type in files:
        return True
    return False


def list_to_str(data):
    if isinstance(data, list):
        return data[0]
    else:
        return data


def missing_lidar_gnss_file(lidar_gnss_config):
    with open(lidar_gnss_config, 'r') as f:
        data = yaml.safe_load(f)
    yaml_dir = os.path.dirname(lidar_gnss_config)
    odometry_dir = os.path.join(yaml_dir, data['odometry_file'])
    point_cloud_dir = os.path.join(yaml_dir,
                                   list_to_str(data['sensor_files_directory']))
    print(f"odometry_dir:{odometry_dir} , point_cloud_dir: {point_cloud_dir}")
    if not os.access(odometry_dir, os.F_OK):
        print('odometry file does not exist')
        return True
    if not file_type_exist(point_cloud_dir, '.pcd'):
        print('pcd file does not exist')
        return True
    return False


def missing_camera_lidar_file(camera_lidar_configs):
    with open(camera_lidar_configs, 'r') as f:
        data = yaml.safe_load(f)
    yaml_dir = os.path.dirname(camera_lidar_configs)
    camera_lidar_pairs_dir = os.path.join(yaml_dir, data['data_path'])
    extrinsics_yaml_dir = os.path.join(yaml_dir, data['extrinsic'])
    intrinsics_yaml_dir = os.path.join(yaml_dir, data['intrinsic'])
    jpg_flag = file_type_exist(camera_lidar_pairs_dir, '.jpg')
    pcd_flag = file_type_exist(camera_lidar_pairs_dir, '.pcd')
    if not (jpg_flag and pcd_flag):
        print('camera_lidar_pairs data error')
        return True
    if not os.access(extrinsics_yaml_dir, os.F_OK):
        print('extrinsics_yaml file does not exist')
        return True
    if not os.access(intrinsics_yaml_dir, os.F_OK):
        print('intrinsics_yaml file does not exist')
        return True
    return False


def missing_calibration_data_file(sample_config_files):
    lidar_file_flag = False
    camera_file_flag = False
    for sample_config_file in sample_config_files:
        with open(sample_config_file, 'r') as f:
            data = yaml.safe_load(f)
            if data['calibration_task'] == 'lidar_to_gnss':
                if (missing_lidar_gnss_file(sample_config_file)):
                    lidar_file_flag = True
            if data['calibration_task'] == 'camera_to_lidar':
                if (missing_camera_lidar_file(sample_config_file)):
                    camera_file_flag = True
    return lidar_file_flag, camera_file_flag


def is_oversize_file(path):
    if getInputDirDataSize(path) >= 1 * 1024 * 1024 * 1024:
        print('The input file is oversize!')
        return True
    return False


def sanity_check(input_folder):
    lidar_gnss_flag = False
    camera_lidar_flag = False
    if is_oversize_file(input_folder):
        err_msg = "The input file is oversize(1G)!"
        print(err_msg)
        return False
    config_flag, config_files = missing_config_file(input_folder)
    if config_flag:
        err_msg = "Missing sample_config.yaml!"
        print(err_msg)
        return False
    if missing_calibration_task(config_files):
        err_msg = "The sample_config.yaml file miss calibration_task config!"
        print(err_msg)
        return False
    lidar_gnss_flag, camera_lidar_flag = missing_calibration_data_file(
        config_files)
    if lidar_gnss_flag and not camera_lidar_flag:
        err_msg = "Missing Lidar_gnss files!"
    elif not lidar_gnss_flag and camera_lidar_flag:
        err_msg = "Missing camera_lidar files!"
    elif lidar_gnss_flag and camera_lidar_flag:
        err_msg = "Missing lidar_gnss and camera_lidar files!"
    else:
        print("%s Passed sanity check." % input_folder)
        return True
    print(err_msg)
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--input_folder",
        action="store",
        default="",
        required=True,
        dest='input_folder',
        help="Specify the input folder where storing extracted sensor messages"
    )
    args = parser.parse_args()

    sanity_check(input_folder=args.input_folder)


if __name__ == "__main__":
    main()
