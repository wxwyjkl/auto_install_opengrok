function log() {
  echo
  echo -e "\033[35m******************************************************\033[0m"
  echo -e "\033[35m[wxwyjkl]: ${1}\033[0m"
  echo -e "\033[35m******************************************************\033[0m"
  echo
}

function logi() {
  echo -e "\033[35m[wxwyjkl-Info]:\033[0m ${1}"
}

function logw() {
  echo -e "\033[33m[wxwyjkl-Warning]:\033[0m ${1}"
}

function loge() {
  echo -e "\033[31m[wxwyjkl-Error]:\033[0m ${1}"
}

function download() {
  local url=$1
  local pkg_name=${url##*/}
  local download_pkg=${DOWNLOAD_DIR}/${pkg_name}
  if [ -f $download_pkg ];then
    logi "Package already downloaded."
  else
    wget $url -P $DOWNLOAD_DIR
    if [ $? -eq 0 ];then
      if [ -f $download_pkg ];then
        logi "Download successfully."
      else
        loge "Download failed, $download_pkg not found!"
        exit -1
      fi
    else
      loge "Download $pkg_name failed!"
      exit -1
    fi
  fi
}

function download_and_install_pkg() {
  download $1
  local url=$1
  local pkg_name=${url##*/}
  local download_pkg=${DOWNLOAD_DIR}/${pkg_name}
  if [[ $download_pkg == *.deb ]]; then
    logi "Install downloaded package: "$download_pkg
    sudo dpkg -i $download_pkg
  fi
}