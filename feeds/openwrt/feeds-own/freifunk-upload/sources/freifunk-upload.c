/*
 * Copyright (C) 2004  Sven-Ola Tuecke  <sven-ola@gmx.de>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

/* Oct 03, 2004
 *
 * This program parses the data, a web browser sends to a 
 * web server when uploading a binary file. It was necessary,
 * because the standard tools awk and sed in a busybox environment
 * are not binary clean (uses C strings which will eat up the
 * binary zeroes)
 */
 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <byteswap.h>
#include <netinet/in.h>

#define ANY_CONTENT_TYPE
#define ROUNDFILESIZE 1024

#if __BYTE_ORDER == __BIG_ENDIAN
#define STORE32_LE(X) bswap_32(X)
#define STORE16_LE(X) bswap_16(X)
#elif __BYTE_ORDER == __LITTLE_ENDIAN
#define STORE32_LE(X) (X)
#define STORE16_LE(X) (X)
#else
#error unkown endianness!
#endif


#define lengthof(array) (sizeof(array)/sizeof(*array))

static const char* S_OUTPUTDIR = "/tmp/";
static const char* S_REQUEST_METHOD_ENV = "REQUEST_METHOD";
static const char* S_REQUEST_METHOD_EXP = "POST";
static const char* S_CONTENT_TYPE_ENV = "CONTENT_TYPE";
static const char* S_CONTENT_TYPE_EXP = "multipart/form-data; boundary=";
static const char* S_CONTENT_DISP = "Content-Disposition:";
static const char* S_CONTENT_DISP_FNM = "filename";
static const char* S_CONTENT_DISP_NAM = "name";
static const char* S_CONTENT_TYPE = "Content-Type:";
#ifndef ANY_CONTENT_TYPE
static const char* S_CONTENT_TYPE_APP = "application/octet-stream";
#endif

uint32_t crc32file(FILE *in, size_t len, char *buf, size_t buflen, uint32_t* pcrc);
uint32_t crc32buf(char *buf, size_t buflen);

int main(int argc, char *argv[], char *environment[])
{
  char buffer[256]; /* Use only x^2, <= ROUNDFILESIZE */
  
  const char *method = getenv(S_REQUEST_METHOD_ENV);
  if ((0 == method) || (0 == *method) || (0 != strcmp(method, S_REQUEST_METHOD_EXP))) {
    fprintf(stderr, "%s=%s expected.\n", S_REQUEST_METHOD_ENV, S_REQUEST_METHOD_EXP);
    return 1;
  }
  
  const char *boundary = getenv(S_CONTENT_TYPE_ENV);
  if ((0 == boundary) || (0 == *boundary) || (0 != strncmp(boundary, S_CONTENT_TYPE_EXP, strlen(S_CONTENT_TYPE_EXP)))) {
    fprintf(stderr, "%s=%s expected.\n", S_CONTENT_TYPE_ENV, S_CONTENT_TYPE_EXP);
    return 1;
  }
  /* Input data is separted by printf("--%s", boundary) */
  boundary += strlen(S_CONTENT_TYPE_EXP);

//  long content_len=atol(getenv(S_CONTENT_LENGTH_ENV)+strlen(S_CONTENT_LENGTH_ENV));
  long content_len;
  sscanf(getenv("CONTENT_LENGTH"),"%ld\n",&content_len);
  printf("CONTENT_LENGTH=%ld\n",content_len,getenv("CONTENT_LENGTH"));

  int eee=0;
  int headers = (0 == 0);
  size_t r = fread(buffer, 1, lengthof(buffer), stdin);
  if (0 < r) {
    size_t w = 0; 
    FILE* outfile = 0;
    int isname = (0 == 1);
    char formvar[64];  /* Name of the form var */
    char outname[128]; /* Filename for output */
    content_len-=r;
    strcpy(formvar, "");
    strcpy(outname, "");
    while (w < r) {
      if (headers) {
        if (0 == strncmp(buffer, S_CONTENT_DISP, strlen(S_CONTENT_DISP))) {
          w += strlen(S_CONTENT_DISP);
          while (w < r && '\n' != buffer[w]) {
            while (w < r && ' ' == buffer[w]) {
              w++;
            }
            int cdl = 0;
            if (w + strlen(S_CONTENT_DISP_FNM) < r && 0 == strncmp(buffer + w, 
              S_CONTENT_DISP_FNM, strlen(S_CONTENT_DISP_FNM))) 
            {
              isname = (0 == 1);
              cdl = strlen(S_CONTENT_DISP_FNM);
            }
            if (w + strlen(S_CONTENT_DISP_NAM) < r && 0 == strncmp(buffer + w, 
              S_CONTENT_DISP_NAM, strlen(S_CONTENT_DISP_NAM)))
            {
              isname = (1 == 1);
              cdl = strlen(S_CONTENT_DISP_NAM);
            }
            if (0 < cdl) {
              w += cdl;
              while (w < r && ' ' == buffer[w]) {
                w++;
              }
              if (w < r && '=' == buffer[w]) {
                w++;
                char c = ' ';
                if (w < r && (('"' == buffer[w]) || ('\'' == buffer[w]))) {
                  c = buffer[w++];
                }
                strcpy(formvar, "");
                strcpy(outname, S_OUTPUTDIR);

                while (w < r && c != buffer[w]) {
                  if (isname) {
                    strncat(formvar, buffer + w, 1);
                    if (lengthof(formvar) - 1 <= strlen(formvar)) {
                      fprintf(stderr, "Form variable name too long: %s.\n", formvar);
                      return 1;
                    }
                  }
                  else {
                    if ('/' == buffer[w] || '\\' == buffer[w] || ':' == buffer[w]) {
                      /* We ignore directory names here */
                      strcpy(outname, S_OUTPUTDIR);
                    }
                    else {
                      strncat(outname, buffer + w, 1);
                      if (lengthof(outname) - 1 <= strlen(outname)) {
                        fprintf(stderr, "Filename too long: %s.\n", outname);
                        return 1;
                      }
                    }
                  }
                  w++;
                }
              }
            }
            while (w < r && ';' != buffer[w] && '\n' != buffer[w]) {
              w++;
            }
            if (w < r && '\n' != buffer[w]) {
              w++;
            }
          }
        }
        else if (0 == strncmp(buffer, S_CONTENT_TYPE, strlen(S_CONTENT_TYPE))) {
          w += strlen(S_CONTENT_TYPE);
          while (w < r && ' ' == buffer[w]) {
            w++;
          }
#ifndef ANY_CONTENT_TYPE
          if (0 != strncmp(buffer + w, S_CONTENT_TYPE_APP, strlen(S_CONTENT_TYPE_APP))) {
            fprintf(stderr, "%s=%s expected.\n", S_CONTENT_TYPE, S_CONTENT_TYPE_APP);
            return 1;
          }
#endif
        }
        else {
          /* Windows sends CR/LF combination */
          while (w < r && '\r' == buffer[w]) w++;
          if (w < r && '\n' == buffer[w]) {
            /* End of headers if newline here */
            headers = 0;
            if (!isname && 0 != outname[strlen(S_OUTPUTDIR)]) {
              outfile = fopen(outname, "w");
              if (0 == outfile) {
                fprintf(stderr, "Cannot write %s.\n", outname);
                return 1;
              }
              printf("ffout=\"%s\"\n", outname);
            }
          }
        }
        /* Search end of string */
        while (w < r && '\n' != buffer[w]) {
          w++;
        }
        if (w < r) {
          w++;
        }
        else {
          fprintf(stderr, "Header too long.\n");
          return 1;
        }
      }
      else {
        /* Not headers, write only half of the buffer
         * so we can determine the boundary if present
         */
        size_t o = lengthof(buffer) / 2 > r ? r : lengthof(buffer) / 2;
        while(!headers && w < o) {
          /* Look for ending boundary */
          int i = 0;
          /* There may be one CR/LF combination at the end */
          if ('\r' == buffer[w + i]) i++;
          if ('\n' == buffer[w + i]) i++;
          if ('-' == buffer[w + i] && '-' == buffer[w + i + 1] && 0 == 
            strncmp(buffer + w + i + 2, boundary, strlen(boundary)))
          {
	    int k= w + i + 2 + strlen(boundary);
		if(buffer[k]=='-' && buffer[k+1]=='-')
		{
		  eee=1;
		}
            headers = 1;
            o = w;
          }
          w++;
        }
        if (0 != outfile) {  
          if (o != fwrite(buffer, 1, o, outfile)) {
            fprintf(stderr, "Error writing %s.\n", outname);
            return 1;
          }
          if (headers) {
            strcpy(outname, S_OUTPUTDIR);
            fclose(outfile);
            outfile = 0;
          }
        }
        else if (isname && 0 != o && 1 < argc ) {
	  printf("%s=\"", formvar);
	  int i; for(i = 0; i < (int)o; i++) printf("%c", buffer[i]);
	  printf("\"\n");
        }
	if(content_len==0){printf("end=zero-len;true\n");return 0;}
        if(eee){printf("end=boundary;true\n");return 0;}
      }
      if (w < r) {
        memmove(buffer, buffer + w, r - w);
        r -= w;
      }
      else {
        r = 0;
      }
      int ll=lengthof(buffer)-r;
      if(ll>content_len)ll=content_len;	
      int rr=fread(buffer + r, 1, ll, stdin);
      content_len-=rr;
      r += rr;
      w = 0;
    }
    if (0 != outfile) {
      fclose(outfile);
      fprintf(stderr, "Ending boundary not found.\n");
      return 1;
    }
  }
  return 0;
}

/**********************************************************************/
/* The following was grabbed and tweaked from the old snippets collection
 * of public domain C code. */

/**********************************************************************\
|* Demonstration program to compute the 32-bit CRC used as the frame  *|
|* check sequence in ADCCP (ANSI X3.66, also known as FIPS PUB 71     *|
|* and FED-STD-1003, the U.S. versions of CCITT's X.25 link-level     *|
|* protocol).  The 32-bit FCS was added via the Federal Register,     *|
|* 1 June 1982, p.23798.  I presume but don't know for certain that   *|
|* this polynomial is or will be included in CCITT V.41, which        *|
|* defines the 16-bit CRC (often called CRC-CCITT) polynomial.  FIPS  *|
|* PUB 78 says that the 32-bit FCS reduces otherwise undetected       *|
|* errors by a factor of 10^-5 over 16-bit FCS.                       *|
\**********************************************************************/

/* Copyright (C) 1986 Gary S. Brown.  You may use this program, or
   code or tables extracted from it, as desired without restriction.*/

/* First, the polynomial itself and its table of feedback terms.  The  */
/* polynomial is                                                       */
/* X^32+X^26+X^23+X^22+X^16+X^12+X^11+X^10+X^8+X^7+X^5+X^4+X^2+X^1+X^0 */
/* Note that we take it "backwards" and put the highest-order term in  */
/* the lowest-order bit.  The X^32 term is "implied"; the LSB is the   */
/* X^31 term, etc.  The X^0 term (usually shown as "+1") results in    */
/* the MSB being 1.                                                    */

/* Note that the usual hardware shift register implementation, which   */
/* is what we're using (we're merely optimizing it by doing eight-bit  */
/* chunks at a time) shifts bits into the lowest-order term.  In our   */
/* implementation, that means shifting towards the right.  Why do we   */
/* do it this way?  Because the calculated CRC must be transmitted in  */
/* order from highest-order term to lowest-order term.  UARTs transmit */
/* characters in order from LSB to MSB.  By storing the CRC this way,  */
/* we hand it to the UART in the order low-byte to high-byte; the UART */
/* sends each low-bit to hight-bit; and the result is transmission bit */
/* by bit from highest- to lowest-order term without requiring any bit */
/* shuffling on our part.  Reception works similarly.                  */

/* The feedback terms table consists of 256, 32-bit entries.  Notes:   */
/*                                                                     */
/*  1. The table can be generated at runtime if desired; code to do so */
/*     is shown later.  It might not be obvious, but the feedback      */
/*     terms simply represent the results of eight shift/xor opera-    */
/*     tions for all combinations of data and CRC register values.     */
/*                                                                     */
/*  2. The CRC accumulation logic is the same for all CRC polynomials, */
/*     be they sixteen or thirty-two bits wide.  You simply choose the */
/*     appropriate table.  Alternatively, because the table can be     */
/*     generated at runtime, you can start by generating the table for */
/*     the polynomial in question and use exactly the same "updcrc",   */
/*     if your application needn't simultaneously handle two CRC       */
/*     polynomials.  (Note, however, that XMODEM is strange.)          */
/*                                                                     */
/*  3. For 16-bit CRCs, the table entries need be only 16 bits wide;   */
/*     of course, 32-bit entries work OK if the high 16 bits are zero. */
/*                                                                     */
/*  4. The values must be right-shifted by eight bits by the "updcrc"  */
/*     logic; the shift must be unsigned (bring in zeroes).  On some   */
/*     hardware you could probably optimize the shift in assembler by  */
/*     using byte-swap instructions.                                   */

static const uint32_t crc_32_tab[] = { /* CRC polynomial 0xedb88320 */
0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f,
0xe963a535, 0x9e6495a3, 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9,
0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c,
0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d, 0x76dc4190, 0x01db7106,
0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d,
0x91646c97, 0xe6635c01, 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7,
0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa,
0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683, 0xe3630b12, 0x94643b84,
0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb,
0x196c3671, 0x6e6b06e7, 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55,
0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28,
0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242,
0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69,
0x616bffd3, 0x166ccf45, 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693,
0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
};

#define UPDC32(octet,crc) (crc_32_tab[((crc) ^ (octet)) & 0xff] ^ ((crc) >> 8))

uint32_t crc32file(FILE *in, size_t len, char *buf, size_t buflen, uint32_t* pcrc)
{
  uint32_t crc;

  if (0 != pcrc) {
    crc = *pcrc;
  }
  else {
    crc = 0xFFFFFFFF;
  }

  while(0 != len) {
    size_t l = fread(buf, 1, len < buflen ? len : buflen, in);
    if (l != (len < buflen ? len : buflen)) {
      return 0xFFFFFFFF;
    }
    len -= l;
    char *p = buf;
    for ( ; l; --l, ++p) {
      crc = UPDC32(*p, crc);
    }
  }

  return crc;
}

uint32_t crc32buf(char *buf, size_t buflen)
{
  uint32_t crc;

  crc = 0xFFFFFFFF;

  while(0 < buflen--) {
    crc = UPDC32(*buf++, crc);
  }

  return crc;
}
