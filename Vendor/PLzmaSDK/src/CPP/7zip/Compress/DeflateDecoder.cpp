#include "StdAfx.h"
#include <zlib.h>
#include "DeflateDecoder.h"

namespace NCompress { namespace NDeflate {
static const UInt32 kBufferSize = 1 << 17;

Z7_COM7F_IMF(CDecoder::Code(ISequentialInStream *inStream,
    ISequentialOutStream *outStream, const UInt64 *, const UInt64 *outSize,
    ICompressProgressInfo *progress))
{
  Byte inBuffer[kBufferSize];
  Byte outBuffer[kBufferSize];
  z_stream stream = {};
  UInt64 totalIn = 0;
  UInt64 totalOut = 0;
  bool inputEnded = false;
  HRESULT result = S_OK;
  int zResult = Z_OK;
  if (inflateInit2(&stream, -MAX_WBITS) != Z_OK)
    return E_FAIL;

  while (zResult != Z_STREAM_END)
  {
    if (stream.avail_in == 0 && !inputEnded)
    {
      UInt32 processed = 0;
      result = inStream->Read(inBuffer, kBufferSize, &processed);
      if (result != S_OK) break;
      stream.next_in = reinterpret_cast<Bytef *>(inBuffer);
      stream.avail_in = processed;
      totalIn += processed;
      inputEnded = processed == 0;
    }
    stream.next_out = reinterpret_cast<Bytef *>(outBuffer);
    stream.avail_out = kBufferSize;
    if (outSize)
    {
      const UInt64 remaining = *outSize - totalOut;
      if (remaining < stream.avail_out)
        stream.avail_out = static_cast<uInt>(remaining);
      if (stream.avail_out == 0) break;
    }
    const uInt before = stream.avail_out;
    zResult = inflate(&stream, Z_NO_FLUSH);
    const UInt32 produced = before - stream.avail_out;
    UInt32 offset = 0;
    while (offset < produced)
    {
      UInt32 written = 0;
      result = outStream->Write(outBuffer + offset, produced - offset, &written);
      if (result != S_OK || written == 0) break;
      offset += written;
      totalOut += written;
    }
    if (result != S_OK || offset != produced)
    {
      if (result == S_OK) result = E_FAIL;
      break;
    }
    if (progress)
    {
      result = progress->SetRatioInfo(&totalIn, &totalOut);
      if (result != S_OK) break;
    }
    if (zResult != Z_OK && zResult != Z_STREAM_END)
    {
      result = S_FALSE;
      break;
    }
    if (inputEnded && stream.avail_in == 0 && produced == 0)
    {
      result = S_FALSE;
      break;
    }
  }
  inflateEnd(&stream);
  if (result != S_OK) return result;
  if (outSize && totalOut != *outSize) return S_FALSE;
  return zResult == Z_STREAM_END || (outSize && totalOut == *outSize) ? S_OK : S_FALSE;
}
}}
