/* -*- c++ -*- ----------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator
   https://www.lammps.org/, Sandia National Laboratories
   LAMMPS development team: developers@lammps.org

   Copyright (2003) Sandia Corporation.  Under the terms of Contract
   DE-AC04-94AL85000 with Sandia Corporation, the U.S. Government retains
   certain rights in this software.  This software is distributed under
   the GNU General Public License.

   See the README file in the top-level LAMMPS directory.
------------------------------------------------------------------------- */

#ifdef FIX_CLASS
// clang-format off
FixStyle(nve2/kk,FixNVE2Kokkos<LMPDeviceType>);
FixStyle(nve2/kk/device,FixNVE2Kokkos<LMPDeviceType>);
FixStyle(nve2/kk/host,FixNVE2Kokkos<LMPHostType>);
// clang-format on
#else

// clang-format off
#ifndef LMP_FIX_NVE2_KOKKOS_H
#define LMP_FIX_NVE2_KOKKOS_H

#include "fix_nve.h"
#include "kokkos_type.h"

namespace LAMMPS_NS {

template<class DeviceType>
class FixNVE2Kokkos;

template <class DeviceType, int RMass>
struct FixNVE2KokkosInitialIntegrateFunctor;

template <class DeviceType, int RMass>
struct FixNVE2KokkosFinalIntegrateFunctor;

template<class DeviceType>
class FixNVE2Kokkos : public FixNVE {
 public:
  FixNVE2Kokkos(class LAMMPS *, int, char **);

  void cleanup_copy();
  void init() override;
  void initial_integrate(int) override;
  void final_integrate() override;
  void fused_integrate(int) override;

  KOKKOS_INLINE_FUNCTION
  void initial_integrate_item(int) const;
  KOKKOS_INLINE_FUNCTION
  void initial_integrate_rmass_item(int) const;
  KOKKOS_INLINE_FUNCTION
  void final_integrate_item(int) const;
  KOKKOS_INLINE_FUNCTION
  void final_integrate_rmass_item(int) const;
  KOKKOS_INLINE_FUNCTION
  void fused_integrate_item(int) const;
  KOKKOS_INLINE_FUNCTION
  void fused_integrate_rmass_item(int) const;

 private:


  typename ArrayTypes<DeviceType>::t_x_array x;
  typename ArrayTypes<DeviceType>::t_v_array v;
  typename ArrayTypes<DeviceType>::t_f_array_const f;
  typename ArrayTypes<DeviceType>::t_float_1d rmass;
  typename ArrayTypes<DeviceType>::t_float_1d mass;
  typename ArrayTypes<DeviceType>::t_int_1d type;
  typename ArrayTypes<DeviceType>::t_int_1d mask;
};

template <class DeviceType, int RMass>
struct FixNVE2KokkosInitialIntegrateFunctor  {
  typedef DeviceType  device_type ;
  FixNVE2Kokkos<DeviceType> c;

  FixNVE2KokkosInitialIntegrateFunctor(FixNVE2Kokkos<DeviceType>* c_ptr):
  c(*c_ptr) {c.cleanup_copy();};
  KOKKOS_INLINE_FUNCTION
  void operator()(const int i) const {
    if (RMass) c.initial_integrate_rmass_item(i);
    else c.initial_integrate_item(i);
  }
};

template <class DeviceType, int RMass>
struct FixNVE2KokkosFinalIntegrateFunctor  {
  typedef DeviceType  device_type ;
  FixNVE2Kokkos<DeviceType> c;

  FixNVE2KokkosFinalIntegrateFunctor(FixNVE2Kokkos<DeviceType>* c_ptr):
  c(*c_ptr) {c.cleanup_copy();};
  KOKKOS_INLINE_FUNCTION
  void operator()(const int i) const {
    if (RMass) c.final_integrate_rmass_item(i);
    else c.final_integrate_item(i);
  }
};

template <class DeviceType, int RMass>
struct FixNVE2KokkosFusedIntegrateFunctor  {
  typedef DeviceType  device_type ;
  FixNVE2Kokkos<DeviceType> c;

  FixNVE2KokkosFusedIntegrateFunctor(FixNVE2Kokkos<DeviceType>* c_ptr):
  c(*c_ptr) {c.cleanup_copy();};
  KOKKOS_INLINE_FUNCTION
  void operator()(const int i) const {
    if (RMass)
      c.fused_integrate_rmass_item(i);
    else
      c.fused_integrate_item(i);
  }
};

}

#endif
#endif

