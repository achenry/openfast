rm -rf build
mkdir build
cd build
cmake .. -DBUILD_OPENFAST_SIMULINK_API=ON -DBUILD_SHARED_LIBS=ON -DMatlab_ROOT_DIR=/Applications/MATLAB_R2022a.app -DDOUBLE_PRECISION=OFF -DCMAKE_INSTALL_NAME_DIR=@loader_path -DCMAKE_MACOSX_RPATH=ON
make -j10 install
