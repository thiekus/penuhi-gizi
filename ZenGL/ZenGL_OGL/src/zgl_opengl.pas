{
 *  Copyright (c) 2012 Andrey Kemka
 *
 *  This software is provided 'as-is', without any express or
 *  implied warranty. In no event will the authors be held
 *  liable for any damages arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute
 *  it freely, subject to the following restrictions:
 *
 *  1. The origin of this software must not be misrepresented;
 *     you must not claim that you wrote the original software.
 *     If you use this software in a product, an acknowledgment
 *     in the product documentation would be appreciated but
 *     is not required.
 *
 *  2. Altered source versions must be plainly marked as such,
 *     and must not be misrepresented as being the original software.
 *
 *  3. This notice may not be removed or altered from any
 *     source distribution.
}
unit zgl_opengl;

{$I zgl_config.cfg}

interface
uses
  {$IFDEF LINUX}
  X, XUtil,
  {$ENDIF}
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF MACOSX}
  MacOSAll,
  {$ENDIF}
  zgl_opengl_all;

const
  TARGET_SCREEN  = 1;
  TARGET_TEXTURE = 2;

function  gl_Create : Boolean;
procedure gl_Destroy;
function  gl_Initialize : Boolean;
procedure gl_ResetState;
procedure gl_LoadEx;

var
  oglzDepth     : Byte;
  oglStencil    : Byte;
  oglFSAA       : Byte;
  oglAnisotropy : Byte;
  oglFOVY       : Single = 45;
  oglzNear      : Single = 0.1;
  oglzFar       : Single = 100;

  oglMode    : Integer = 2; // 2D/3D Modes
  oglTarget  : Integer = TARGET_SCREEN;
  oglTargetW : Integer;
  oglTargetH : Integer;
  oglWidth   : Integer;
  oglHeight  : Integer;

  oglVRAMUsed : LongWord;

  oglRenderer      : UTF8String;
  oglExtensions    : UTF8String;
  ogl3DAccelerator : Boolean;
  oglCanVSync      : Boolean;
  oglCanAnisotropy : Boolean;
  oglCanS3TC       : Boolean;
  oglCanAutoMipMap : Boolean;
  oglCanFBO        : Boolean;
  oglCanPBuffer    : Boolean;
  oglMaxTexSize    : Integer;
  oglMaxFBOSize    : Integer;
  oglMaxAnisotropy : Integer;
  oglMaxTexUnits   : Integer;
  oglSeparate      : Boolean;

  {$IFDEF LINUX}
  oglXExtensions : UTF8String;
  oglPBufferMode : Integer;
  oglContext     : GLXContext;
  oglVisualInfo  : PXVisualInfo;
  oglAttr        : array[ 0..31 ] of Integer;
  {$ENDIF}
  {$IFDEF WINDOWS}
  oglContext    : HGLRC;
  oglfAttr      : array[ 0..1  ] of Single = ( 0, 0 );
  ogliAttr      : array[ 0..31 ] of Integer;
  oglFormat     : Integer;
  oglFormats    : LongWord;
  oglFormatDesc : TPixelFormatDescriptor;
  {$ENDIF}
  {$IFDEF MACOSX}
  oglDevice   : GDHandle;
  oglContext  : TAGLContext;
  oglFormat   : TAGLPixelFormat;
  oglAttr     : array[ 0..31 ] of LongWord;
  {$ENDIF}

implementation
uses
  zgl_application,
  zgl_screen,
  zgl_window,
  zgl_log,
  zgl_utils;

function gl_Create : Boolean;
  var
  {$IFDEF LINUX}
    i, j : Integer;
  {$ENDIF}
  {$IFDEF WINDOWS}
    i           : Integer;
    pixelFormat : Integer;
  {$ENDIF}
  {$IFDEF MACOSX}
    i : Integer;
  {$ENDIF}
begin
  Result := FALSE;

  if not InitGL() Then
    begin
      log_Add( 'Cannot load GL library' );
      exit;
    end;

{$IFDEF LINUX}
  if not glXQueryExtension( scrDisplay, i, j ) Then
    begin
      u_Error( 'GLX Extension not found' );
      exit;
    end else log_Add( 'GLX Extension - ok' );

  oglzDepth := 24;
  repeat
    FillChar( oglAttr[ 0 ], Length( oglAttr ) * 4, None );
    oglAttr[ 0  ] := GLX_RGBA;
    oglAttr[ 1  ] := GL_TRUE;
    oglAttr[ 2  ] := GLX_RED_SIZE;
    oglAttr[ 3  ] := 8;
    oglAttr[ 4  ] := GLX_GREEN_SIZE;
    oglAttr[ 5  ] := 8;
    oglAttr[ 6  ] := GLX_BLUE_SIZE;
    oglAttr[ 7  ] := 8;
    oglAttr[ 8  ] := GLX_ALPHA_SIZE;
    // NVIDIA sucks!
    oglAttr[ 9  ] := 8 * Byte( not appInitedToHandle );
    oglAttr[ 10 ] := GLX_DOUBLEBUFFER;
    oglAttr[ 11 ] := GL_TRUE;
    oglAttr[ 12 ] := GLX_DEPTH_SIZE;
    oglAttr[ 13 ] := oglzDepth;
    i := 14;
    if oglStencil > 0 Then
      begin
        oglAttr[ i     ] := GLX_STENCIL_SIZE;
        oglAttr[ i + 1 ] := oglStencil;
        INC( i, 2 );
      end;
    if oglFSAA > 0 Then
      begin
        oglAttr[ i     ] := GLX_SAMPLES_SGIS;
        oglAttr[ i + 1 ] := oglFSAA;
      end;

    log_Add( 'glXChooseVisual: zDepth = ' + u_IntToStr( oglzDepth ) + '; ' + 'stencil = ' + u_IntToStr( oglStencil ) + '; ' + 'fsaa = ' + u_IntToStr( oglFSAA )  );
    oglVisualInfo := glXChooseVisual( scrDisplay, scrDefault, @oglAttr[ 0 ] );
    if ( not Assigned( oglVisualInfo ) and ( oglzDepth = 1 ) ) Then
      begin
        if oglFSAA = 0 Then
          break
        else
          begin
            oglzDepth := 24;
            DEC( oglFSAA, 2 );
          end;
      end else
        if not Assigned( oglVisualInfo ) Then DEC( oglzDepth, 8 );
  if oglzDepth = 0 Then oglzDepth := 1;
  until Assigned( oglVisualInfo );

  if not Assigned( oglVisualInfo ) Then
    begin
      u_Error( 'Cannot choose visual info.' );
      exit;
    end;
{$ENDIF}
{$IFDEF WINDOWS}
  wnd_Create( wndWidth, wndHeight );

  FillChar( oglFormatDesc, SizeOf( TPixelFormatDescriptor ), 0 );
  with oglFormatDesc do
    begin
      nSize        := SizeOf( TPIXELFORMATDESCRIPTOR );
      nVersion     := 1;
      dwFlags      := PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER;
      iPixelType   := PFD_TYPE_RGBA;
      cColorBits   := 24;
      cAlphabits   := 8;
      cDepthBits   := 24;
      cStencilBits := oglStencil;
      iLayerType   := PFD_MAIN_PLANE;
    end;

  pixelFormat := ChoosePixelFormat( wndDC, @oglFormatDesc );
  if pixelFormat = 0 Then
    begin
      u_Error( 'Cannot choose pixel format' );
      exit;
    end;

  if not SetPixelFormat( wndDC, pixelFormat, @oglFormatDesc ) Then
    begin
      u_Error( 'Cannot set pixel format' );
      exit;
    end;

  oglContext := wglCreateContext( wndDC );
  if ( oglContext = 0 ) Then
    begin
      u_Error( 'Cannot create OpenGL context' );
      exit;
    end;

  if not wglMakeCurrent( wndDC, oglContext ) Then
    begin
      u_Error( 'Cannot set current OpenGL context' );
      exit;
    end;

  wglChoosePixelFormatARB := gl_GetProc( 'wglChoosePixelFormatARB' );
  if Assigned( wglChoosePixelFormatARB ) Then
    begin
      oglzDepth := 24;

      repeat
        FillChar( ogliAttr[ 0 ], Length( ogliAttr ) * 4, 0 );
        ogliAttr[ 0  ] := WGL_ACCELERATION_ARB;
        ogliAttr[ 1  ] := WGL_FULL_ACCELERATION_ARB;
        ogliAttr[ 2  ] := WGL_DRAW_TO_WINDOW_ARB;
        ogliAttr[ 3  ] := GL_TRUE;
        ogliAttr[ 4  ] := WGL_SUPPORT_OPENGL_ARB;
        ogliAttr[ 5  ] := GL_TRUE;
        ogliAttr[ 6  ] := WGL_DOUBLE_BUFFER_ARB;
        ogliAttr[ 7  ] := GL_TRUE;
        ogliAttr[ 8  ] := WGL_PIXEL_TYPE_ARB;
        ogliAttr[ 9  ] := WGL_TYPE_RGBA_ARB;
        ogliAttr[ 10 ] := WGL_COLOR_BITS_ARB;
        ogliAttr[ 11 ] := 24;
        ogliAttr[ 12 ] := WGL_RED_BITS_ARB;
        ogliAttr[ 13 ] := 8;
        ogliAttr[ 14 ] := WGL_GREEN_BITS_ARB;
        ogliAttr[ 15 ] := 8;
        ogliAttr[ 16 ] := WGL_BLUE_BITS_ARB;
        ogliAttr[ 17 ] := 8;
        ogliAttr[ 18 ] := WGL_ALPHA_BITS_ARB;
        ogliAttr[ 19 ] := 8;
        ogliAttr[ 20 ] := WGL_DEPTH_BITS_ARB;
        ogliAttr[ 21 ] := oglzDepth;
        i := 22;
        if oglStencil > 0 Then
          begin
            ogliAttr[ i     ] := WGL_STENCIL_BITS_ARB;
            ogliAttr[ i + 1 ] := oglStencil;
            INC( i, 2 );
          end;
        if oglFSAA > 0 Then
          begin
            ogliAttr[ i     ] := WGL_SAMPLE_BUFFERS_ARB;
            ogliAttr[ i + 1 ] := GL_TRUE;
            ogliAttr[ i + 2 ] := WGL_SAMPLES_ARB;
            ogliAttr[ i + 3 ] := oglFSAA;
          end;

        log_Add( 'wglChoosePixelFormatARB: zDepth = ' + u_IntToStr( oglzDepth ) + '; ' + 'stencil = ' + u_IntToStr( oglStencil ) + '; ' + 'fsaa = ' + u_IntToStr( oglFSAA )  );
        wglChoosePixelFormatARB( wndDC, @ogliAttr, @oglfAttr, 1, @oglFormat, @oglFormats );
        if ( oglFormat = 0 ) and ( oglzDepth < 16 ) Then
          begin
            if oglFSAA <= 0 Then
              break
            else
              begin
                oglzDepth := 24;
                DEC( oglFSAA, 2 );
              end;
          end else
            DEC( oglzDepth, 8 );
      until oglFormat <> 0;
    end;

  if oglFormat = 0 Then
    begin
      oglzDepth := 24;
      oglFSAA   := 0;
      oglFormat := pixelFormat;
      log_Add( 'ChoosePixelFormat: zDepth = ' + u_IntToStr( oglzDepth ) + '; ' + 'stencil = ' + u_IntToStr( oglStencil )  );
    end;

  wglMakeCurrent( wndDC, 0 );
  wglDeleteContext( oglContext );
  wnd_Destroy();
  wndFirst := FALSE;
{$ENDIF}
{$IFDEF MACOSX}
  if not InitAGL() Then
    begin
      log_Add( 'Cannot load AGL library' );
      exit;
    end;

  oglzDepth := 24;
  repeat
    FillChar( oglAttr[ 0 ], Length( oglAttr ) * 4, AGL_NONE );
    oglAttr[ 0  ] := AGL_RGBA;
    oglAttr[ 1  ] := AGL_RED_SIZE;
    oglAttr[ 2  ] := 8;
    oglAttr[ 3  ] := AGL_GREEN_SIZE;
    oglAttr[ 4  ] := 8;
    oglAttr[ 5  ] := AGL_BLUE_SIZE;
    oglAttr[ 6  ] := 8;
    oglAttr[ 7  ] := AGL_ALPHA_SIZE;
    oglAttr[ 8  ] := 8;
    oglAttr[ 9  ] := AGL_DOUBLEBUFFER;
    oglAttr[ 10 ] := AGL_DEPTH_SIZE;
    oglAttr[ 11 ] := oglzDepth;
    i := 12;
    if oglStencil > 0 Then
      begin
        oglAttr[ i     ] := AGL_STENCIL_SIZE;
        oglAttr[ i + 1 ] := oglStencil;
        INC( i, 2 );
      end;
    if oglFSAA > 0 Then
      begin
        oglAttr[ i     ] := AGL_SAMPLE_BUFFERS_ARB;
        oglAttr[ i + 1 ] := 1;
        oglAttr[ i + 2 ] := AGL_SAMPLES_ARB;
        oglAttr[ i + 3 ] := oglFSAA;
        INC( i, 4 );
      end;

    log_Add( 'aglChoosePixelFormat: zDepth = ' + u_IntToStr( oglzDepth ) + '; ' + 'stencil = ' + u_IntToStr( oglStencil ) + '; ' + 'fsaa = ' + u_IntToStr( oglFSAA ) );
    DMGetGDeviceByDisplayID( DisplayIDType( scrDisplay ), oglDevice, FALSE );
    oglFormat := aglChoosePixelFormat( @oglDevice, 1, @oglAttr[ 0 ] );
    if ( not Assigned( oglFormat ) and ( oglzDepth = 1 ) ) Then
      begin
        if oglFSAA = 0 Then
          break
        else
          begin
            oglzDepth := 24;
            DEC( oglFSAA, 2 );
          end;
      end else
        if not Assigned( oglFormat ) Then DEC( oglzDepth, 8 );
  if oglzDepth = 0 Then oglzDepth := 1;
  until Assigned( oglFormat );

  if not Assigned( oglFormat ) Then
    begin
      u_Error( 'Cannot choose pixel format.' );
      exit;
    end;
{$ENDIF}

  Result := TRUE;
end;

procedure gl_Destroy;
begin
{$IFDEF LINUX}
  if not glXMakeCurrent( scrDisplay, None, nil ) Then
    u_Error( 'Cannot release current OpenGL context');

  glXDestroyContext( scrDisplay, oglContext );
{$ENDIF}
{$IFDEF WINDOWS}
  if not wglMakeCurrent( wndDC, 0 ) Then
    u_Error( 'Cannot release current OpenGL context' );

  wglDeleteContext( oglContext );
{$ENDIF}
{$IFDEF MACOSX}
  aglDestroyPixelFormat( oglFormat );
  if aglSetCurrentContext( nil ) = GL_FALSE Then
    u_Error( 'Cannot release current OpenGL context' );

  aglDestroyContext( oglContext );
  FreeAGL();
{$ENDIF}

  FreeGL();
end;

function gl_Initialize : Boolean;
begin
  Result := FALSE;
{$IFDEF LINUX}
  oglContext := glXCreateContext( scrDisplay, oglVisualInfo, nil, TRUE );
  if not Assigned( oglContext ) Then
    begin
      oglContext := glXCreateContext( scrDisplay, oglVisualInfo, nil, FALSE );
      if not Assigned( oglContext ) Then
        begin
          u_Error( 'Cannot create OpenGL context' );
          exit;
        end;
    end;
  if not glXMakeCurrent( scrDisplay, wndHandle, oglContext ) Then
    begin
      u_Error( 'Cannot set current OpenGL context' );
      exit;
    end;
{$ENDIF}
{$IFDEF WINDOWS}
  if not SetPixelFormat( wndDC, oglFormat, @oglFormatDesc ) Then
    begin
      u_Error( 'Cannot set pixel format' );
      exit;
    end;

  oglContext := wglCreateContext( wndDC );
  if ( oglContext = 0 ) Then
    begin
      u_Error( 'Cannot create OpenGL context' );
      exit;
    end;
  if not wglMakeCurrent( wndDC, oglContext ) Then
    begin
      u_Error( 'Cannot set current OpenGL context' );
      exit;
    end;
{$ENDIF}
{$IFDEF MACOSX}
  oglContext := aglCreateContext( oglFormat, nil );
  if not Assigned( oglContext ) Then
    begin
      u_Error( 'Cannot create OpenGL context' );
      exit;
    end;
  if aglSetDrawable( oglContext, GetWindowPort( wndHandle ) ) = GL_FALSE Then
    begin
      u_Error( 'Cannot set Drawable' );
      exit;
    end;
  if aglSetCurrentContext( oglContext ) = GL_FALSE Then
    begin
      u_Error( 'Cannot set current OpenGL context' );
      exit;
    end;
{$ENDIF}

  oglRenderer := glGetString( GL_RENDERER );
  log_Add( 'GL_VERSION: ' + glGetString( GL_VERSION ) );
  log_Add( 'GL_RENDERER: ' + oglRenderer );

{$IFDEF LINUX}
  ogl3DAccelerator := oglRenderer <> 'Software Rasterizer';
{$ENDIF}
{$IFDEF WINDOWS}
  ogl3DAccelerator := oglRenderer <> 'GDI Generic';
{$ENDIF}
{$IFDEF MACOSX}
  ogl3DAccelerator := oglRenderer <> 'Apple Software Renderer';
{$ENDIF}
  if not ogl3DAccelerator Then
    u_Warning( 'Cannot find 3D-accelerator! Application run in software-mode, it''s very slow' );

  gl_LoadEx();
  gl_ResetState();

  Result := TRUE;
end;

procedure gl_ResetState;
begin
  glHint( GL_LINE_SMOOTH_HINT,            GL_NICEST );
  glHint( GL_POLYGON_SMOOTH_HINT,         GL_NICEST );
  glHint( GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST );
  glHint( GL_FOG_HINT,                    GL_DONT_CARE );
  glShadeModel( GL_SMOOTH );

  glClearColor( 0, 0, 0, 0 );

  glDepthFunc ( GL_LEQUAL );
  glClearDepth( 1.0 );

  glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
  glAlphaFunc( GL_GREATER, 0 );

  if oglSeparate Then
    begin
      glBlendEquation( GL_FUNC_ADD_EXT );
      glBlendFuncSeparate( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA );
    end;

  glDisable( GL_BLEND );
  glDisable( GL_ALPHA_TEST );
  glDisable( GL_DEPTH_TEST );
  glDisable( GL_TEXTURE_2D );
  glEnable ( GL_NORMALIZE );
end;

procedure gl_LoadEx;
  {$IFDEF LINUX}
  var
    i, j : Integer;
  {$ENDIF}
begin
  oglExtensions := glGetString( GL_EXTENSIONS );

  // Texture size
  glGetIntegerv( GL_MAX_TEXTURE_SIZE, @oglMaxTexSize );
  log_Add( 'GL_MAX_TEXTURE_SIZE: ' + u_IntToStr( oglMaxTexSize ) );

  glCompressedTexImage2D := gl_GetProc( 'glCompressedTexImage2D' );
  oglCanS3TC := gl_IsSupported( 'GL_EXT_texture_compression_s3tc', oglExtensions );
  log_Add( 'GL_EXT_TEXTURE_COMPRESSION_S3TC: ' + u_BoolToStr( oglCanS3TC ) );

  oglCanAutoMipMap := gl_IsSupported( 'GL_SGIS_generate_mipmap', oglExtensions );
  log_Add( 'GL_SGIS_GENERATE_MIPMAP: ' + u_BoolToStr( oglCanAutoMipMap ) );

  // Multitexturing
  glGetIntegerv( GL_MAX_TEXTURE_UNITS_ARB, @oglMaxTexUnits );
  log_Add( 'GL_MAX_TEXTURE_UNITS_ARB: ' + u_IntToStr( oglMaxTexUnits ) );

  // Anisotropy
  oglCanAnisotropy := gl_IsSupported( 'GL_EXT_texture_filter_anisotropic', oglExtensions );
  if oglCanAnisotropy Then
    begin
      glGetIntegerv( GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, @oglMaxAnisotropy );
      oglAnisotropy := oglMaxAnisotropy;
    end else
      oglAnisotropy := 0;
  log_Add( 'GL_EXT_TEXTURE_FILTER_ANISOTROPIC: ' + u_BoolToStr( oglCanAnisotropy ) );
  log_Add( 'GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT: ' + u_IntToStr( oglMaxAnisotropy ) );

  glBlendEquation     := gl_GetProc( 'glBlendEquation' );
  glBlendFuncSeparate := gl_GetProc( 'glBlendFuncSeparate' );
  oglSeparate := Assigned( glBlendEquation ) and Assigned( glBlendFuncSeparate ) and gl_IsSupported( 'GL_EXT_blend_func_separate', oglExtensions );
  log_Add( 'GL_EXT_BLEND_FUNC_SEPARATE: ' + u_BoolToStr( oglSeparate ) );

  // FBO
  glBindRenderbuffer := gl_GetProc( 'glBindRenderbuffer' );
  if Assigned( glBindRenderbuffer ) Then
    begin
      oglCanFBO                 := TRUE;
      glIsRenderbuffer          := gl_GetProc( 'glIsRenderbuffer'          );
      glDeleteRenderbuffers     := gl_GetProc( 'glDeleteRenderbuffers'     );
      glGenRenderbuffers        := gl_GetProc( 'glGenRenderbuffers'        );
      glRenderbufferStorage     := gl_GetProc( 'glRenderbufferStorage'     );
      glIsFramebuffer           := gl_GetProc( 'glIsFramebuffer'           );
      glBindFramebuffer         := gl_GetProc( 'glBindFramebuffer'         );
      glDeleteFramebuffers      := gl_GetProc( 'glDeleteFramebuffers'      );
      glGenFramebuffers         := gl_GetProc( 'glGenFramebuffers'         );
      glCheckFramebufferStatus  := gl_GetProc( 'glCheckFramebufferStatus'  );
      glFramebufferTexture2D    := gl_GetProc( 'glFramebufferTexture2D'    );
      glFramebufferRenderbuffer := gl_GetProc( 'glFramebufferRenderbuffer' );

      glGetIntegerv( GL_MAX_RENDERBUFFER_SIZE, @oglMaxFBOSize );
      log_Add( 'GL_MAX_RENDERBUFFER_SIZE: ' + u_IntToStr( oglMaxFBOSize ) );
    end else
      oglCanFBO := FALSE;
   log_Add( 'GL_EXT_FRAMEBUFFER_OBJECT: ' + u_BoolToStr( oglCanFBO ) );

  // PBUFFER
{$IFDEF LINUX}
  oglxExtensions := glXQueryServerString( scrDisplay, scrDefault, GLX_EXTENSIONS );
  glXQueryVersion( scrDisplay, i, j );
  if ( i * 10 + j >= 13 ) Then
    oglPBufferMode := 1
  else
    if gl_IsSupported( 'GLX_SGIX_fbconfig', oglXExtensions ) and gl_IsSupported( 'GLX_SGIX_pbuffer', oglXExtensions ) Then
        oglPBufferMode := 2
    else
      oglPBufferMode := 0;
  oglCanPBuffer := oglPBufferMode <> 0;
  if oglPBufferMode = 2 Then
    log_Add( 'GLX_SGIX_PBUFFER: TRUE' )
  else
    log_Add( 'GLX_PBUFFER: ' + u_BoolToStr( oglCanPBuffer ) );

  case oglPBufferMode of
    1:
      begin
        glXGetVisualFromFBConfig := gl_GetProc( 'glXGetVisualFromFBConfig' );
        glXChooseFBConfig        := gl_GetProc( 'glXChooseFBConfig' );
        glXCreatePbuffer         := gl_GetProc( 'glXCreatePbuffer' );
        glXDestroyPbuffer        := gl_GetProc( 'glXDestroyPbuffer' );
      end;
    2:
      begin
        glXGetVisualFromFBConfig := gl_GetProc( 'glXGetVisualFromFBConfigSGIX' );
        glXChooseFBConfig        := gl_GetProc( 'glXChooseFBConfigSGIX' );
        glXCreateGLXPbufferSGIX  := gl_GetProc( 'glXCreateGLXPbufferSGIX' );
        glXDestroyGLXPbufferSGIX := gl_GetProc( 'glXDestroyGLXPbufferSGIX' );
      end;
  end;
{$ENDIF}
{$IFDEF WINDOWS}
  wglCreatePbufferARB := gl_GetProc( 'wglCreatePbuffer' );
  if Assigned( wglCreatePbufferARB ) and Assigned( wglChoosePixelFormatARB ) Then
    begin
      oglCanPBuffer          := TRUE;
      wglGetPbufferDCARB     := gl_GetProc( 'wglGetPbufferDC'     );
      wglReleasePbufferDCARB := gl_GetProc( 'wglReleasePbufferDC' );
      wglDestroyPbufferARB   := gl_GetProc( 'wglDestroyPbuffer'   );
    end else
      oglCanPBuffer := FALSE;
  log_Add( 'WGL_PBUFFER: ' + u_BoolToStr( oglCanPBuffer ) );
{$ENDIF}
{$IFDEF MACOSX}
  oglCanPBuffer := Assigned( aglCreatePBuffer );
  log_Add( 'AGL_PBUFFER: ' + u_BoolToStr( oglCanPBuffer ) );
{$ENDIF}

  // WaitVSync
{$IFDEF LINUX}
  glXSwapIntervalSGI := gl_GetProc( 'glXSwapIntervalSGI' );
  oglCanVSync        := Assigned( glXSwapIntervalSGI );
{$ENDIF}
{$IFDEF WINDOWS}
  wglSwapInterval := gl_GetProc( 'wglSwapInterval' );
  oglCanVSync     := Assigned( wglSwapInterval );
{$ENDIF}
{$IFDEF MACOSX}
  if aglSetInt( oglContext, AGL_SWAP_INTERVAL, 1 ) = GL_TRUE Then
    oglCanVSync := TRUE
  else
    oglCanVSync := FALSE;
  aglSetInt( oglContext, AGL_SWAP_INTERVAL, Byte( scrVSync ) );
{$ENDIF}
  if oglCanVSync Then
    scr_SetVSync( scrVSync );
  log_Add( 'Support WaitVSync: ' + u_BoolToStr( oglCanVSync ) );
end;

end.
