
#include "lammpsplugin.h"

#include "version.h"

#include <cstring>

#include "fix_nve2.h"
#include "fix_nve2_kokkos.h"

using namespace LAMMPS_NS;

static Fix *nve2creator(LAMMPS *lmp, int argc, char **argv)
{
  return new FixNVE2(lmp, argc, argv);
}

static Fix *nve2kkcreator(LAMMPS *lmp, int argc, char **argv)
{
  return new FixNVE2Kokkos<LMPDeviceType>(lmp, argc, argv);
}

static Fix *nve2kkhostcreator(LAMMPS *lmp, int argc, char **argv)
{
  return new FixNVE2Kokkos<LMPHostType>(lmp, argc, argv);
}

static Fix *nve2kkdevicecreator(LAMMPS *lmp, int argc, char **argv)
{
  return new FixNVE2Kokkos<LMPDeviceType>(lmp, argc, argv);
}

extern "C" void lammpsplugin_init(void *lmp, void *handle, void *regfunc)
{
  lammpsplugin_t plugin;
  lammpsplugin_regfunc register_plugin = (lammpsplugin_regfunc) regfunc;

  // register plain nve2 fix style
  plugin.version = LAMMPS_VERSION;
  plugin.style = "fix";
  plugin.name = "nve2";
  plugin.info = "NVE2 variant fix style v1.0";
  plugin.author = "Axel Kohlmeyer (akohlmey@gmail.com)";
  plugin.creator.v2 = (lammpsplugin_factory2 *) &nve2creator;
  plugin.handle = handle;
  (*register_plugin)(&plugin, lmp);

  // register nve2/kk pair style
  plugin.name = "nve2/kk";
  plugin.info = "nve2/kk variant pair style v1.0";
  plugin.author = "Trung Nguyen (ndactrung@gmail.com)";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &nve2kkcreator;
  (*register_plugin)(&plugin, lmp);

  // also register nve2/kk/host pair style. only need to update changed fields
  plugin.name = "nve2/kk/host";
  plugin.info = "nve2/kk variant pair style for Kokkos v1.0";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &nve2kkhostcreator;
  (*register_plugin)(&plugin, lmp);

  // also register nve2/kk/device pair style. only need to update changed fields
  plugin.name = "nve2/kk/device";
  plugin.info = "nve2/kk variant pair style for Kokkos v1.0";
  plugin.creator.v1 = (lammpsplugin_factory1 *) &nve2kkdevicecreator;
  (*register_plugin)(&plugin, lmp);
}
