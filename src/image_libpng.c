/*
 *  A Z-Machine
 *  Copyright (C) 2000 Andrew Hunter
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * Generic image routines, using libpng
 */

#include "../config.h"

#ifdef HAVE_LIBPNG

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <png.h>

#include "image.h"

struct image_data
{
  ZFile* file;
  int offset;

  png_uint_32 width, height;
  int depth, colour;

  png_bytep  image;
  png_bytep* row;
};

struct file_data
{
  ZFile* file;
  int    pos;
};

static void image_read(png_structp png_ptr,
		       png_bytep   data,
		       png_size_t len)
{
  struct file_data* fl;
  void* stuff;

  fl = png_get_io_ptr(png_ptr);

  stuff = read_block(fl->file, fl->pos, fl->pos+len);
  fl->pos += len;
  memcpy(data, stuff, len);
  free(stuff);
}

static image_data* iload(image_data* resin, ZFile* file, int offset, int realread)
{
  struct file_data fl;

  image_data* res;
  png_structp png;
  png_infop   png_info;
  png_infop   end_info;

  int x;

  res = resin;

  png = png_create_read_struct(PNG_LIBPNG_VER_STRING,
			       (png_voidp)NULL,
			       NULL,
			       NULL);
  if (!png)
    return NULL;
  
  png_info = png_create_info_struct(png);
  if (!png_info)
    {
      png_destroy_read_struct(&png, NULL, NULL);
      return NULL;
    }

  end_info = png_create_info_struct(png);
  if (!end_info)
    {
      png_destroy_read_struct(&png, &png_info, NULL);
      return NULL;
    }
  
  fl.file = file;
  fl.pos  = offset;
  png_set_read_fn(png, &fl, image_read);

  if (res == NULL)
    res = malloc(sizeof(image_data));

  res->file   = file;
  res->offset = offset;
  res->row    = NULL;
  res->image  = NULL;

  png_read_info(png, png_info);
  png_get_IHDR(png, png_info,
	       &res->width, &res->height,
	       &res->depth, &res->colour,
	       NULL, NULL, NULL);

  /* We want 8-bit RGB data only */
  if (res->colour == PNG_COLOR_TYPE_GRAY ||
      res->colour == PNG_COLOR_TYPE_GRAY_ALPHA)
    png_set_gray_to_rgb(png);
  if (res->depth <= 8)
    png_set_expand(png);
  if (png_get_valid(png, png_info, PNG_INFO_tRNS)) 
    png_set_expand(png);
  if (res->depth == 16)
    png_set_strip_16(png);

  /* Update our information accordingly */
  png_read_update_info(png, png_info);
  png_get_IHDR(png, png_info,
	       &res->width, &res->height,
	       &res->depth, &res->colour,
	       NULL, NULL, NULL);

  res->row = malloc(sizeof(png_bytep)*res->height);
  res->image = malloc(sizeof(png_byte)*png_get_rowbytes(png, png_info)*res->height);

  for (x=0; x<res->height; x++)
    {
      res->row[x] = res->image + (x*png_get_rowbytes(png, png_info));
    }

  if (realread)
    {
      png_read_image(png, res->row);
      
      png_read_end(png, end_info);
    }
      
  png_destroy_read_struct(&png, &png_info, &end_info);

  return res;
}

image_data*    image_load  (ZFile* file, int offset)
{
  return iload(NULL, file, offset, 0);
}

void image_unload(image_data* data)
{
  if (data == NULL)
    return;

  if (data->image != NULL)
    free(data->image);
  if (data->row != NULL)
    free(data->row);

  free(data);
}

void image_unload_rgb(image_data* data)
{
  if (data == NULL)
    return;

  if (data->image != NULL)
    free(data->image);
  if (data->row != NULL)
    free(data->row);

  data->image = NULL;
  data->row   = NULL;
}

int image_width(image_data* data)
{
  return data->width;
}

int image_height(image_data* data)
{
  return data->height;
}

unsigned char* image_rgb(image_data* data)
{
  if (data->image == NULL)
    {
      if (iload(data, data->file, data->offset, 1) == NULL)
	{
	  return NULL;
	}
    }

  return data->image;
}

#endif