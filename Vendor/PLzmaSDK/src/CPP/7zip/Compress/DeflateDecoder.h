#ifndef ZIP7_INC_DEFLATE_DECODER_H
#define ZIP7_INC_DEFLATE_DECODER_H

#include "../../Common/MyCom.h"
#include "../ICoder.h"

namespace NCompress { namespace NDeflate {
class CDecoder Z7_final: public ICompressCoder, public CMyUnknownImp
{
  Z7_COM_QI_BEGIN2(ICompressCoder)
  Z7_COM_QI_END
  Z7_COM_ADDREF_RELEASE
  Z7_IFACE_COM7_IMP(ICompressCoder)
};
}}
#endif
