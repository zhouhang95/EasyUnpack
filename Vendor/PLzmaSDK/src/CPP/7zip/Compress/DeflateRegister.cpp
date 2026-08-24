#include "StdAfx.h"
#include "../Common/RegisterCodec.h"
#include "DeflateDecoder.h"

namespace NCompress { namespace NDeflate {
REGISTER_CODEC_CREATE(CreateDecoder, CDecoder())
REGISTER_CODEC_2(Deflate, CreateDecoder, NULL, 0x40108, "Deflate")
}}
