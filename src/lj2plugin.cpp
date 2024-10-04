
#include "lammpsplugin.h"

#include "version.h"

#include <cstring>

#include "pair_lj_cut2_kokkos.h"

using namespace LAMMPS_NS;

static Pair *ljcut2kkcreator(LAMMPS *lmp)
{
    return new PairLJCut2Kokkos<LMPDeviceType>(lmp);
}

static Pair *ljcut2kkhostcreator(LAMMPS *lmp)
{
    return new PairLJCut2Kokkos<LMPHostType>(lmp);
}

static Pair *ljcut2kkdevicecreator(LAMMPS *lmp)
{
    return new PairLJCut2Kokkos<LMPDeviceType>(lmp);
}

extern "C" void lammpsplugin_init(void *lmp, void *handle, void *regfunc)
{
  lammpsplugin_t plugin;
  lammpsplugin_regfunc register_plugin = (lammpsplugin_regfunc) regfunc;

  // register plain lj/cut2 pair style
  plugin.version = LAMMPS_VERSION;
  plugin.style = "pair";
  plugin.name = "lj/cut2/kk";
  plugin.info = "lj/cut variant pair style v1.0";
  plugin.author = "Trung Nguyen (ndactrung@gmail.com)";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &ljcut2kkcreator;
  plugin.handle = handle;
  (*register_plugin)(&plugin, lmp);

  // also register lj/cut2/kk/host pair style. only need to update changed fields
  plugin.name = "lj/cut2/kk/host";
  plugin.info = "lj/cut variant pair style for Kokkos v1.0";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &ljcut2kkhostcreator;
  (*register_plugin)(&plugin, lmp);

  // also register lj/cut2/kk/device pair style. only need to update changed fields
  plugin.name = "lj/cut2/kk/device";
  plugin.info = "lj/cut variant pair style for Kokkos v1.0";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &ljcut2kkdevicecreator;
  (*register_plugin)(&plugin, lmp);
}
