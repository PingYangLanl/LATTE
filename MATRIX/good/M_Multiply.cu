/*!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Copyright 2010.  Los Alamos National Security, LLC. This material was    !
! produced under U.S. Government contract DE-AC52-06NA25396 for Los Alamos !
! National Laboratory (LANL), which is operated by Los Alamos National     !
! Security, LLC for the U.S. Department of Energy. The U.S. Government has !
! rights to use, reproduce, and distribute this software.  NEITHER THE     !
! GOVERNMENT NOR LOS ALAMOS NATIONAL SECURITY, LLC MAKES ANY WARRANTY,     !
! EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY FOR THE USE OF THIS         !
! SOFTWARE.  If software is modified to produce derivative works, such     !
! modified software should be clearly marked, so as not to confuse it      !
! with the version available from LANL.                                    !
!                                                                          !
! Additionally, this program is free software; you can redistribute it     !
! and/or modify it under the terms of the GNU General Public License as    !
! published by the Free Software Foundation; version 2.0 of the License.   !
! Accordingly, this program is distributed in the hope that it will be     !
! useful, but WITHOUT ANY WARRANTY; without even the implied warranty of   !
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General !
! Public License for more details.                                         !
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!*/

#include "Matrix.h"

extern cublasHandle_t* handle;
extern int ndevices;
extern int nblocks;
extern cudaStream_t stream[];
extern cudaEvent_t event[];

void M_Multiply(Matrix A, Matrix B, Matrix C) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ZERO, C.Device[0], C.DM);
#elif REALSIZE==8
  cublasDgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ZERO, C.Device[0], C.DM);
#endif

}

void M_Multiply3(Matrix A, Matrix B, Matrix C) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ONE, C.Device[0], C.DM);
#elif REALSIZE==8
  cublasDgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ONE, C.Device[0], C.DM);
#endif

}

void M_MultiplyTranspose(Matrix A, Matrix B, Matrix C) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSgemm(handle[0], CUBLAS_OP_T, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ZERO, C.Device[0], C.DM);
#elif REALSIZE==8
  cublasDgemm(handle[0], CUBLAS_OP_T, CUBLAS_OP_N, A.DM, B.DN, A.DN, &ONE, A.Device[0], A.DM, B.Device[0], B.DM, &ZERO, C.Device[0], C.DM);
#endif

}

void M_Multiply(REAL *scalar1, Matrix A, Matrix B, REAL *scalar2, Matrix C) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, scalar1, A.Device[0], A.DM, B.Device[0], B.DM, scalar2, C.Device[0], C.DM);
#elif REALSIZE==8
  cublasDgemm(handle[0], CUBLAS_OP_N, CUBLAS_OP_N, A.DM, B.DN, A.DN, scalar1, A.Device[0], A.DM, B.Device[0], B.DM, scalar2, C.Device[0], C.DM);
#endif

}

// Matrix multiplication on multiple GPUs
void M_MultiplyMgpu(REAL *scalar1, Matrix A, Matrix B, REAL *scalar2, Matrix C, Matrix C2) {

  int idevice = 0;          // GPU 0  
  int cdev;
  int ks;
  int iblock1, iblock2;     // indices for blocks to multiply    
  int oblock;               // index for output block
  int kblock, kpblock;      // which sub-block
  int sub = A.DN / nblocks; // size of each block

  // Save current device
  cudaGetDevice(&cdev);

  //printf("DN = %d  nblocks = %d  sub = %d\n", A.DN, nblocks, sub);
  kblock = 0;
  ks = 0;

  for (int k = 0; k < nblocks; k++) {
    kpblock = 0;

    for (int kp = 0; kp < nblocks; kp++) {

      iblock1 = kblock * A.DN;
      iblock2 = kpblock * A.DN;

      oblock = kp * sub * sub + k * A.DN * sub;

      idevice = k % ndevices;
      cudaSetDevice(idevice);

      //printf("idevice = %d  iblock1 = %d  iblock2 = %d  oblock = %d\n", idevice, iblock1, iblock2, oblock);

      // Associate stream with cublas call
      //cublasSetStream(handle[idevice], stream[idevice]);

      // Multiply - results in sub x sub block
#if REALSIZE==4
      cublasSgemm(handle[idevice], CUBLAS_OP_N, CUBLAS_OP_T, sub, sub, A.DN, scalar1, &A.Device[idevice]+iblock1, sub, B.Device[idevice]+iblock2, sub, scalar2, C2.Device[idevice]+oblock, sub);
#elif REALSIZE==8
      cublasDgemm(handle[idevice], CUBLAS_OP_N, CUBLAS_OP_T, sub, sub, A.DN, scalar1, A.Device[idevice]+iblock1, sub, B.Device[idevice]+iblock2, sub, scalar2, C2.Device[idevice]+oblock, sub);
#endif

      ks++;
      kpblock += sub;
    }
    
    kblock += sub;
  }

  // Wait till all multiplies are done
  for (int d = 0; d < ndevices; ++d) {
    cudaSetDevice(d);
    cudaStreamSynchronize(stream[d]);
  }

  // Reassemble matrix blocks from stripes to grid
  M_AssembleMgpu(C, C2, sub);

/*
  // Sum up C's across GPUs
  cudaSetDevice(0);
  if (ndevices > 1) {
    for (int d = 1; d < ndevices; ++d) {
      M_MultiplyScalarSumMgpu(d, &ONE, C2, C, stream);
    }
  } 

  // Wait till all sums are done
  cudaStreamSynchronize(stream[0]);
*/

  // Restore device
  cudaSetDevice(cdev);
}

void M_Multiply(REAL k, Matrix A, Matrix B) {

  int msize = A.DM * A.DN;
  int size = msize >> 1;
  int blockCount = (int) ceil((float)size/(float)NUM_THREADS);

  MultiplyScalarMatrixKernel<<<blockCount,NUM_THREADS>>>(msize, k, A.Device[0], B.Device[0]);

}

void M_MultiplyAdd(REAL k, Matrix A, REAL k2,  Matrix B, Matrix C) {

  int size = A.DM * A.DN;
  int blockCount = (int) ceil((float)size/(float)NUM_THREADS);

  MultiplyScalarMatrixAddKernel<<<blockCount,NUM_THREADS>>>(size, k, A.Device[0], k2, B.Device[0], C.Device[0]);
}

void M_MultiplyAdd(REAL k, Matrix A, Matrix B, Matrix C) {

  int size = A.DM * A.DN;
  int blockCount = (int) ceil((float)size/(float)NUM_THREADS);

  cudaSetDevice(0);

  MultiplyScalarMatrixAddMatrixKernel<<<blockCount,NUM_THREADS>>>(size, k, A.Device[0], B.Device[0], C.Device[0]);
}

void M_MultiplySub(REAL k, Matrix A, REAL k2,  Matrix B, Matrix C) {

  int size = A.DM * A.DN;
  int blockCount = (int) ceil((float)size/(float)NUM_THREADS);

  cudaSetDevice(0);

  MultiplyScalarMatrixSubKernel<<<blockCount,NUM_THREADS>>>(size, k, A.Device[0], k2, B.Device[0], C.Device[0]);
}

void M_MultiplySub(REAL k, Matrix A, Matrix B, Matrix C) {

  int size = A.DM * A.DN;
  int blockCount = (int) ceil((float)size/(float)NUM_THREADS);

  cudaSetDevice(0);

  MultiplyScalarMatrixSubMatrixKernel<<<blockCount,NUM_THREADS>>>(size, k, A.Device[0], B.Device[0], C.Device[0]);
}

