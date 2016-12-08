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

#include "Kernels.h"	

__global__ void CGIterateKernel(int const M, REAL *p0, REAL *tmpmat, REAL *r0, REAL *bo, REAL *error2_ptr) {

  REAL r0vec, p0vec, r1vec, xalpha, xbeta, error2;

  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  const int grid_size = blockDim.x * gridDim.x;

  // Create intermeduate sums
  extern __shared__ REAL sdata[];
  sdata[threadIdx.x] = GPU_ZERO;
  __syncthreads();

  error2=GPU_ZERO;

  int i = tid;
  while (i < M) {

    r0vec = GPU_ZERO;
    p0vec = GPU_ZERO;
    r1vec = GPU_ZERO;

    for (int offset=i*M; offset<i*M+M; offset++) {
      p0vec+=(p0[offset]*tmpmat[offset]);
      r0vec+=(r0[offset]*r0[offset]);
    }

    if (p0vec>GPU_ZERO) xalpha = r0vec/p0vec;
    else xalpha=GPU_ZERO;

    for (int offset=i*M; offset<i*M+M; offset++) {
      bo[offset]+=(xalpha*p0[offset]);
      r0[offset]+=(xalpha*tmpmat[offset]);
      r1vec+=(r0[offset]*r0[offset]);
    }

    error2 += r1vec;
    if (r0vec>GPU_ZERO) xbeta = r1vec/r0vec;
    else xbeta=GPU_ZERO;

    for (int offset=i*M; offset<i*M+M; offset++) {
      p0[offset]=xbeta*p0[offset] - r0[offset];
      //p0[offset]= r0[offset] - xbeta*p0[offset];
    }

    i += grid_size;

  }

  sdata[threadIdx.x]=error2;

  // make sure all intermediate sums have been calculated
  __syncthreads();

  // Reduce the values in shared memory
  int blockSize = blockDim.x;

  switch (blockSize)
  {
    case 1024:
      if (threadIdx.x < 512) sdata[threadIdx.x] += sdata[threadIdx.x + 512];
      __syncthreads();
    case 512:
      if (threadIdx.x < 256) sdata[threadIdx.x] += sdata[threadIdx.x + 256];
      __syncthreads();
    case 256:
      if (threadIdx.x < 128) sdata[threadIdx.x] += sdata[threadIdx.x + 128];
      __syncthreads();
    case 128:
       if (threadIdx.x < 64) sdata[threadIdx.x] += sdata[threadIdx.x + 64];
      __syncthreads();
    break;
  }

  if (threadIdx.x < 32) {

      volatile REAL* s_ptr = sdata;

      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 32];
      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 16];
      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 8];
      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 4];
      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 2];
      s_ptr[threadIdx.x] += s_ptr[threadIdx.x + 1];

  }

    // write result for this block to global mem
    if (threadIdx.x == 0) error2_ptr[blockIdx.x] = sdata[0];
}
