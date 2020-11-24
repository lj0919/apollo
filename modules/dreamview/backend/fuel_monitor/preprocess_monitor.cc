/******************************************************************************
 * Copyright 2019 The Apollo Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************/

#include "modules/dreamview/backend/fuel_monitor/preprocess_monitor.h"

#include "gflags/gflags.h"
#include "google/protobuf/descriptor.h"
#include "google/protobuf/message.h"
#include "google/protobuf/util/json_util.h"

#include "cyber/common/file.h"
#include "modules/common/adapters/adapter_gflags.h"
#include "modules/common/configs/vehicle_config_helper.h"
#include "modules/dreamview/backend/common/dreamview_gflags.h"
#include "modules/dreamview/backend/hmi/vehicle_manager.h"

namespace apollo {
namespace dreamview {

using apollo::common::VehicleConfigHelper;
using cyber::common::PathExists;
using google::protobuf::util::MessageToJsonString;

using Json = nlohmann::json;

DEFINE_string(progress_topic, "/apollo/dreamview/progress",
              "Sensor calibration preprocess progress topic name.");

PreprocessMonitor::PreprocessMonitor()
    : node_(cyber::CreateNode("progress_monitor")) {
  InitReaders();
  LoadConfiguration();
}

PreprocessMonitor::~PreprocessMonitor() { Stop(); }

void PreprocessMonitor::InitReaders() {
  node_->CreateReader<Progress>(
      FLAGS_progress_topic, [this](const std::shared_ptr<Progress>& progress) {
        this->OnProgress(progress);
      });
}

void PreprocessMonitor::LoadConfiguration() {
  const std::string& vehicle_dir =
      VehicleManager::Instance()->GetVehicleDataPath();
  std::string preprocess_config_path =
      vehicle_dir + "dreamview_conf/precrocess_table.pb.txt";
  if (!PathExists(preprocess_config_path)) {
    AWARN << "No corresponding data collection table file found in "
          << vehicle_dir << ". Using default one instead.";
    preprocess_config_path = FLAGS_default_preprocess_config_path;
  }

  ACHECK(cyber::common::GetProtoFromFile(preprocess_config_path,
                                         &preprocess_table_))
      << "Unable to parse preprocess configuration from file "
      << preprocess_config_path;

  std::string json_string;
  MessageToJsonString(preprocess_table_, &json_string);
  current_status_json_ = Json::parse(json_string);

  ADEBUG << "Configuration loaded.";
}

void PreprocessMonitor::Start() {
  if (!enabled_) {
    current_status_json_.clear();
  }
  enabled_ = true;
}

void PreprocessMonitor::Stop() { enabled_ = false; }

void PreprocessMonitor::OnProgress(const std::shared_ptr<Progress>& progress) {
  if (!enabled_) {
    return;
  }

  {
    boost::unique_lock<boost::shared_mutex> writer_lock(mutex_);
    current_status_json_["progress"] = progress->percentage();
    current_status_json_["logString"] = progress->log_string();
  }
}

nlohmann::json PreprocessMonitor::GetProgressAsJson() {
  boost::unique_lock<boost::shared_mutex> reader_lock(mutex_);
  return current_status_json_;
}

}  // namespace dreamview
}  // namespace apollo
