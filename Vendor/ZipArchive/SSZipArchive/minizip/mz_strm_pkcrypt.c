/* mz_strm_pkcrypt.c -- Code for traditional PKWARE encryption
   part of the minizip-ng project

   Copyright (C) Nathan Moinvaziri
      https://github.com/zlib-ng/minizip-ng
   Copyright (C) 1998-2005 Gilles Vollant
      Modifications for Info-ZIP crypting
      https://www.winimage.com/zLibDll/minizip.html
   Copyright (C) 2003 Terry Thorsen

   This code is a modified version of crypting code in Info-ZIP distribution

   Copyright (C) 1990-2000 Info-ZIP.  All rights reserved.

   This program is distributed under the terms of the same license as zlib.
   See the accompanying LICENSE file for the full text of the license.

   This encryption code is a direct transcription of the algorithm from
   Roger Schlafly, described by Phil Katz in the file appnote.txt. This
   file (appnote.txt) is distributed with the PKZIP program (even in the
   version without encryption capabilities).
*/

#include "mz.h"
#include "mz_crypt.h"
#include "mz_strm.h"
#include "mz_strm_pkcrypt.h"

/***************************************************************************/

static mz_stream_vtbl mz_stream_pkcrypt_vtbl = {
    mz_stream_pkcrypt_open,
    mz_stream_pkcrypt_is_open,
    mz_stream_pkcrypt_read,
    mz_stream_pkcrypt_write,
    mz_stream_pkcrypt_tell,
    mz_stream_pkcrypt_seek,
    mz_stream_pkcrypt_close,
    mz_stream_pkcrypt_error,
    mz_stream_pkcrypt_create,
    mz_stream_pkcrypt_delete,
    mz_stream_pkcrypt_get_prop_int64,
    mz_stream_pkcrypt_set_prop_int64
};

/***************************************************************************/

typedef struct mz_stream_pkcrypt_s {
    mz_stream       stream;
    int32_t         error;
    int16_t         initialized;
    uint8_t         buffer[UINT16_MAX];
    int64_t         total_in;
    int64_t         max_total_in;
    int64_t         total_out;
    uint32_t        keys[3];          /* keys defining the pseudo-random sequence */
    uint8_t         verify1;
    uint8_t         verify2;
    const char      *password;
} mz_stream_pkcrypt;

/***************************************************************************/

#define mz_stream_pkcrypt_decode(strm, c)                                   \
    (mz_stream_pkcrypt_update_keys(strm,                                    \
        c ^= mz_stream_pkcrypt_decrypt_byte(strm)))

#define mz_stream_pkcrypt_encode(strm, c, t)                                \
    (t = mz_stream_pkcrypt_decrypt_byte(strm),                              \
        mz_stream_pkcrypt_update_keys(strm, (uint8_t)c), (uint8_t)(t^(c)))

/***************************************************************************/

static uint8_t mz_stream_pkcrypt_decrypt_byte(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;

    unsigned temp; /* POTENTIAL BUG:  temp*(temp^1) may overflow in an */
                   /* unpredictable manner on 16-bit systems; not a problem */
                   /* with any known compiler so far, though. */

    temp = pkcrypt->keys[2] | 2;
    return (uint8_t)(((temp * (temp ^ 1)) >> 8) & 0xff);
}

/* EasyUnpack: inline raw CRC updates; immutable table supports concurrent readers. */
static const uint32_t easyunpack_crc_table[256] = {
    0x00000000U, 0x77073096U, 0xee0e612cU, 0x990951baU, 0x076dc419U, 0x706af48fU, 0xe963a535U, 0x9e6495a3U,
    0x0edb8832U, 0x79dcb8a4U, 0xe0d5e91eU, 0x97d2d988U, 0x09b64c2bU, 0x7eb17cbdU, 0xe7b82d07U, 0x90bf1d91U,
    0x1db71064U, 0x6ab020f2U, 0xf3b97148U, 0x84be41deU, 0x1adad47dU, 0x6ddde4ebU, 0xf4d4b551U, 0x83d385c7U,
    0x136c9856U, 0x646ba8c0U, 0xfd62f97aU, 0x8a65c9ecU, 0x14015c4fU, 0x63066cd9U, 0xfa0f3d63U, 0x8d080df5U,
    0x3b6e20c8U, 0x4c69105eU, 0xd56041e4U, 0xa2677172U, 0x3c03e4d1U, 0x4b04d447U, 0xd20d85fdU, 0xa50ab56bU,
    0x35b5a8faU, 0x42b2986cU, 0xdbbbc9d6U, 0xacbcf940U, 0x32d86ce3U, 0x45df5c75U, 0xdcd60dcfU, 0xabd13d59U,
    0x26d930acU, 0x51de003aU, 0xc8d75180U, 0xbfd06116U, 0x21b4f4b5U, 0x56b3c423U, 0xcfba9599U, 0xb8bda50fU,
    0x2802b89eU, 0x5f058808U, 0xc60cd9b2U, 0xb10be924U, 0x2f6f7c87U, 0x58684c11U, 0xc1611dabU, 0xb6662d3dU,
    0x76dc4190U, 0x01db7106U, 0x98d220bcU, 0xefd5102aU, 0x71b18589U, 0x06b6b51fU, 0x9fbfe4a5U, 0xe8b8d433U,
    0x7807c9a2U, 0x0f00f934U, 0x9609a88eU, 0xe10e9818U, 0x7f6a0dbbU, 0x086d3d2dU, 0x91646c97U, 0xe6635c01U,
    0x6b6b51f4U, 0x1c6c6162U, 0x856530d8U, 0xf262004eU, 0x6c0695edU, 0x1b01a57bU, 0x8208f4c1U, 0xf50fc457U,
    0x65b0d9c6U, 0x12b7e950U, 0x8bbeb8eaU, 0xfcb9887cU, 0x62dd1ddfU, 0x15da2d49U, 0x8cd37cf3U, 0xfbd44c65U,
    0x4db26158U, 0x3ab551ceU, 0xa3bc0074U, 0xd4bb30e2U, 0x4adfa541U, 0x3dd895d7U, 0xa4d1c46dU, 0xd3d6f4fbU,
    0x4369e96aU, 0x346ed9fcU, 0xad678846U, 0xda60b8d0U, 0x44042d73U, 0x33031de5U, 0xaa0a4c5fU, 0xdd0d7cc9U,
    0x5005713cU, 0x270241aaU, 0xbe0b1010U, 0xc90c2086U, 0x5768b525U, 0x206f85b3U, 0xb966d409U, 0xce61e49fU,
    0x5edef90eU, 0x29d9c998U, 0xb0d09822U, 0xc7d7a8b4U, 0x59b33d17U, 0x2eb40d81U, 0xb7bd5c3bU, 0xc0ba6cadU,
    0xedb88320U, 0x9abfb3b6U, 0x03b6e20cU, 0x74b1d29aU, 0xead54739U, 0x9dd277afU, 0x04db2615U, 0x73dc1683U,
    0xe3630b12U, 0x94643b84U, 0x0d6d6a3eU, 0x7a6a5aa8U, 0xe40ecf0bU, 0x9309ff9dU, 0x0a00ae27U, 0x7d079eb1U,
    0xf00f9344U, 0x8708a3d2U, 0x1e01f268U, 0x6906c2feU, 0xf762575dU, 0x806567cbU, 0x196c3671U, 0x6e6b06e7U,
    0xfed41b76U, 0x89d32be0U, 0x10da7a5aU, 0x67dd4accU, 0xf9b9df6fU, 0x8ebeeff9U, 0x17b7be43U, 0x60b08ed5U,
    0xd6d6a3e8U, 0xa1d1937eU, 0x38d8c2c4U, 0x4fdff252U, 0xd1bb67f1U, 0xa6bc5767U, 0x3fb506ddU, 0x48b2364bU,
    0xd80d2bdaU, 0xaf0a1b4cU, 0x36034af6U, 0x41047a60U, 0xdf60efc3U, 0xa867df55U, 0x316e8eefU, 0x4669be79U,
    0xcb61b38cU, 0xbc66831aU, 0x256fd2a0U, 0x5268e236U, 0xcc0c7795U, 0xbb0b4703U, 0x220216b9U, 0x5505262fU,
    0xc5ba3bbeU, 0xb2bd0b28U, 0x2bb45a92U, 0x5cb36a04U, 0xc2d7ffa7U, 0xb5d0cf31U, 0x2cd99e8bU, 0x5bdeae1dU,
    0x9b64c2b0U, 0xec63f226U, 0x756aa39cU, 0x026d930aU, 0x9c0906a9U, 0xeb0e363fU, 0x72076785U, 0x05005713U,
    0x95bf4a82U, 0xe2b87a14U, 0x7bb12baeU, 0x0cb61b38U, 0x92d28e9bU, 0xe5d5be0dU, 0x7cdcefb7U, 0x0bdbdf21U,
    0x86d3d2d4U, 0xf1d4e242U, 0x68ddb3f8U, 0x1fda836eU, 0x81be16cdU, 0xf6b9265bU, 0x6fb077e1U, 0x18b74777U,
    0x88085ae6U, 0xff0f6a70U, 0x66063bcaU, 0x11010b5cU, 0x8f659effU, 0xf862ae69U, 0x616bffd3U, 0x166ccf45U,
    0xa00ae278U, 0xd70dd2eeU, 0x4e048354U, 0x3903b3c2U, 0xa7672661U, 0xd06016f7U, 0x4969474dU, 0x3e6e77dbU,
    0xaed16a4aU, 0xd9d65adcU, 0x40df0b66U, 0x37d83bf0U, 0xa9bcae53U, 0xdebb9ec5U, 0x47b2cf7fU, 0x30b5ffe9U,
    0xbdbdf21cU, 0xcabac28aU, 0x53b39330U, 0x24b4a3a6U, 0xbad03605U, 0xcdd70693U, 0x54de5729U, 0x23d967bfU,
    0xb3667a2eU, 0xc4614ab8U, 0x5d681b02U, 0x2a6f2b94U, 0xb40bbe37U, 0xc30c8ea1U, 0x5a05df1bU, 0x2d02ef8dU,
};

static uint8_t mz_stream_pkcrypt_update_keys(void *stream, uint8_t c) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    uint8_t buf = c;

    pkcrypt->keys[0] = (pkcrypt->keys[0] >> 8) ^ easyunpack_crc_table[(pkcrypt->keys[0] ^ buf) & 0xff];

    pkcrypt->keys[1] += pkcrypt->keys[0] & 0xff;
    pkcrypt->keys[1] *= 134775813L;
    pkcrypt->keys[1] += 1;

    buf = (uint8_t)(pkcrypt->keys[1] >> 24);
    pkcrypt->keys[2] = (pkcrypt->keys[2] >> 8) ^ easyunpack_crc_table[(pkcrypt->keys[2] ^ buf) & 0xff];

    return (uint8_t)c;
}

static void mz_stream_pkcrypt_init_keys(void *stream, const char *password) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;

    pkcrypt->keys[0] = 305419896L;
    pkcrypt->keys[1] = 591751049L;
    pkcrypt->keys[2] = 878082192L;

    while (*password != 0) {
        mz_stream_pkcrypt_update_keys(stream, (uint8_t)*password);
        password += 1;
    }
}

/***************************************************************************/

int32_t mz_stream_pkcrypt_open(void *stream, const char *path, int32_t mode) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    uint16_t t = 0;
    int16_t i = 0;
    uint8_t verify1 = 0;
    uint8_t verify2 = 0;
    uint8_t header[MZ_PKCRYPT_HEADER_SIZE];
    const char *password = path;

    pkcrypt->total_in = 0;
    pkcrypt->total_out = 0;
    pkcrypt->initialized = 0;

    if (mz_stream_is_open(pkcrypt->stream.base) != MZ_OK)
        return MZ_OPEN_ERROR;

    if (!password)
        password = pkcrypt->password;
    if (!password)
        return MZ_PARAM_ERROR;

    mz_stream_pkcrypt_init_keys(stream, password);

    if (mode & MZ_OPEN_MODE_WRITE) {
        /* First generate RAND_HEAD_LEN - 2 random bytes. */
        mz_crypt_rand(header, MZ_PKCRYPT_HEADER_SIZE - 2);

        /* Encrypt random header (last two bytes is high word of crc) */
        for (i = 0; i < MZ_PKCRYPT_HEADER_SIZE - 2; i++)
            header[i] = mz_stream_pkcrypt_encode(stream, header[i], t);

        header[i++] = mz_stream_pkcrypt_encode(stream, pkcrypt->verify1, t);
        header[i++] = mz_stream_pkcrypt_encode(stream, pkcrypt->verify2, t);

        if (mz_stream_write(pkcrypt->stream.base, header, sizeof(header)) != sizeof(header))
            return MZ_WRITE_ERROR;

        pkcrypt->total_out += MZ_PKCRYPT_HEADER_SIZE;
    } else if (mode & MZ_OPEN_MODE_READ) {
        if (mz_stream_read(pkcrypt->stream.base, header, sizeof(header)) != sizeof(header))
            return MZ_READ_ERROR;

        for (i = 0; i < MZ_PKCRYPT_HEADER_SIZE - 2; i++)
            header[i] = mz_stream_pkcrypt_decode(stream, header[i]);

        verify1 = mz_stream_pkcrypt_decode(stream, header[i++]);
        verify2 = mz_stream_pkcrypt_decode(stream, header[i++]);

        /* Older versions used 2 byte check, newer versions use 1 byte check. */
        MZ_UNUSED(verify1);
        if ((verify2 != 0) && (verify2 != pkcrypt->verify2))
            return MZ_PASSWORD_ERROR;

        pkcrypt->total_in += MZ_PKCRYPT_HEADER_SIZE;
    }

    pkcrypt->initialized = 1;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_is_open(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    if (!pkcrypt->initialized)
        return MZ_OPEN_ERROR;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_read(void *stream, void *buf, int32_t size) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    uint8_t *buf_ptr = (uint8_t *)buf;
    int32_t bytes_to_read = size;
    int32_t read = 0;
    int32_t i = 0;

    if ((int64_t)bytes_to_read > (pkcrypt->max_total_in - pkcrypt->total_in))
        bytes_to_read = (int32_t)(pkcrypt->max_total_in - pkcrypt->total_in);

    read = mz_stream_read(pkcrypt->stream.base, buf, bytes_to_read);

    for (i = 0; i < read; i++)
        buf_ptr[i] = mz_stream_pkcrypt_decode(stream, buf_ptr[i]);

    if (read > 0)
        pkcrypt->total_in += read;

    return read;
}

int32_t mz_stream_pkcrypt_write(void *stream, const void *buf, int32_t size) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    const uint8_t *buf_ptr = (const uint8_t *)buf;
    int32_t bytes_to_write = sizeof(pkcrypt->buffer);
    int32_t total_written = 0;
    int32_t written = 0;
    int32_t i = 0;
    uint16_t t = 0;

    if (size < 0)
        return MZ_PARAM_ERROR;

    do {
        if (bytes_to_write > (size - total_written))
            bytes_to_write = (size - total_written);

        for (i = 0; i < bytes_to_write; i += 1) {
            pkcrypt->buffer[i] = mz_stream_pkcrypt_encode(stream, *buf_ptr, t);
            buf_ptr += 1;
        }

        written = mz_stream_write(pkcrypt->stream.base, pkcrypt->buffer, bytes_to_write);
        if (written < 0)
            return written;

        total_written += written;
    } while (total_written < size && written > 0);

    pkcrypt->total_out += total_written;
    return total_written;
}

int64_t mz_stream_pkcrypt_tell(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return mz_stream_tell(pkcrypt->stream.base);
}

int32_t mz_stream_pkcrypt_seek(void *stream, int64_t offset, int32_t origin) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return mz_stream_seek(pkcrypt->stream.base, offset, origin);
}

int32_t mz_stream_pkcrypt_close(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->initialized = 0;
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_error(void *stream) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    return pkcrypt->error;
}

void mz_stream_pkcrypt_set_password(void *stream, const char *password) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->password = password;
}

void mz_stream_pkcrypt_set_verify(void *stream, uint8_t verify1, uint8_t verify2) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    pkcrypt->verify1 = verify1;
    pkcrypt->verify2 = verify2;
}

void mz_stream_pkcrypt_get_verify(void *stream, uint8_t *verify1, uint8_t *verify2) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    *verify1 = pkcrypt->verify1;
    *verify2 = pkcrypt->verify2;
}

int32_t mz_stream_pkcrypt_get_prop_int64(void *stream, int32_t prop, int64_t *value) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN:
        *value = pkcrypt->total_in;
        break;
    case MZ_STREAM_PROP_TOTAL_OUT:
        *value = pkcrypt->total_out;
        break;
    case MZ_STREAM_PROP_TOTAL_IN_MAX:
        *value = pkcrypt->max_total_in;
        break;
    case MZ_STREAM_PROP_HEADER_SIZE:
        *value = MZ_PKCRYPT_HEADER_SIZE;
        break;
    case MZ_STREAM_PROP_FOOTER_SIZE:
        *value = 0;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

int32_t mz_stream_pkcrypt_set_prop_int64(void *stream, int32_t prop, int64_t value) {
    mz_stream_pkcrypt *pkcrypt = (mz_stream_pkcrypt *)stream;
    switch (prop) {
    case MZ_STREAM_PROP_TOTAL_IN_MAX:
        pkcrypt->max_total_in = value;
        break;
    default:
        return MZ_EXIST_ERROR;
    }
    return MZ_OK;
}

void *mz_stream_pkcrypt_create(void **stream) {
    mz_stream_pkcrypt *pkcrypt = NULL;

    pkcrypt = (mz_stream_pkcrypt *)calloc(1, sizeof(mz_stream_pkcrypt));
    if (pkcrypt)
        pkcrypt->stream.vtbl = &mz_stream_pkcrypt_vtbl;
    if (stream)
        *stream = pkcrypt;

    return pkcrypt;
}

void mz_stream_pkcrypt_delete(void **stream) {
    mz_stream_pkcrypt *pkcrypt = NULL;
    if (!stream)
        return;
    pkcrypt = (mz_stream_pkcrypt *)*stream;
    if (pkcrypt)
        free(pkcrypt);
    *stream = NULL;
}

void *mz_stream_pkcrypt_get_interface(void) {
    return (void *)&mz_stream_pkcrypt_vtbl;
}
