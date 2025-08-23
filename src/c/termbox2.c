/*
 * termbox2.c - Implementation file for termbox2 single-header library
 * 
 * This file provides the implementation for termbox2 by defining TB_IMPL
 * before including the header. This allows FPM to compile termbox2 as a
 * standard C library without external dependencies.
 */

#define TB_IMPL
#include "termbox2.h"