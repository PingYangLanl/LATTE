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

void M_MultiplyScalarSum(REAL *scalar, Matrix A, Matrix B) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSaxpy(handle[0], A.DM*A.DN, scalar, A.Device[0], 1, B.Device[0], 1);
#elif REALSIZE==8
  cublasDaxpy(handle[0], A.DM*A.DN, scalar, A.Device[0], 1, B.Device[0], 1);
#endif

}

void M_MultiplyScalarSumMgpu(int idevice, REAL *scalar, Matrix A, Matrix B, cudaStream_t stream[]) {

  cudaSetDevice(0);

  cudaMemcpy(A.Device[0], B.Device[idevice], A.DM*A.DN*sizeof(REAL), cudaMemcpyDefault); 

#if REALSIZE==4
  cublasSaxpy(handle[0], A.DM*A.DN, scalar, A.Device[0], 1, B.Device[0], 1);
#elif REALSIZE==8
  cublasDaxpy(handle[0], A.DM*A.DN, scalar, A.Device[0], 1, B.Device[0], 1);
#endif

}

void M_MultiplyScalarSumMgpu(REAL *scalar, Matrix A, Matrix B) {

  int cdev;
  int sub = A.DN / nblocks;
  int size = A.DN * sub;

  // Get current device
  cudaGetDevice(&cdev);

  for (int d = 0; d < ndevices; ++d) {

    cudaSetDevice(d);

    for (int b = d; b < nblocks; b += ndevices) {

#if REALSIZE==4
      cublasSaxpy(handle[d], size, scalar, A.Device[d]+b*size, 1, B.Device[d]+b*size, 1);
#elif REALSIZE==8
      cublasDaxpy(handle[d], size, scalar, A.Device[d]+b*size, 1, B.Device[d]+b*size, 1);
#endif

    }
  }

  // Wait till done
  M_Wait();

  // Restore device
  cudaSetDevice(cdev);
}

void M_MultiplyScalarSumMgpu(REAL *scalar, Matrix A, Matrix B, int d) {

  int sub = A.DN / nblocks;
  int size = A.DN * sub;
  

  for (int b = d; b < nblocks; b += ndevices) {

#if REALSIZE==4
    cublasSaxpy(handle[d], size, scalar, A.Device[d]+b*size, 1, B.Device[d]+b*size, 1);
#elif REALSIZE==8
    cublasDaxpy(handle[d], size, scalar, A.Device[d]+b*size, 1, B.Device[d]+b*size, 1);
#endif

    }
}

 
void M_MultiplyScalarSum(int i, REAL *scalar, Matrix A, Matrix B) {

  cudaSetDevice(0);

#if REALSIZE==4
  cublasSaxpy(handle[0], A.DM, scalar, &A.Device[0][i*A.DM], 1, &B.Device[0][i*B.DM], 1);
#elif REALSIZE==8
  cublasDaxpy(handle[0], A.DM, scalar, &A.Device[0][i*A.DM], 1, &B.Device[0][i*B.DM], 1);
#endif

}
