program test_context_validation
  ! Test program to validate documentation examples for Context Object Pattern
  use fortui_core
  use fortui_context
  use fortui_widgets
  implicit none

  type(fortui_context_t), pointer :: ctx
  logical :: running, save_clicked

  write(*,*) "Testing context-aware API from README examples..."

  ! Test basic context usage from documentation
  ctx => create_context()
  
  if (.not. associated(ctx)) then
    write(*,*) "ERROR: Failed to create context"
    stop 1
  end if
  
  ! Initialize with context-aware API
  call ui_init_with_context(ctx, "auto", 80, 25, "Context Demo")
  
  if (.not. ctx%initialized) then
    write(*,*) "ERROR: Context initialization failed"
    stop 1
  end if
  
  write(*,*) "SUCCESS: Context created and initialized"
  write(*,*) "Backend:", trim(ctx%active_backend)
  write(*,*) "Window size:", ctx%window_width, "x", ctx%window_height
  
  ! Test single frame
  call ui_frame_begin_with_context(ctx)
  
  if (.not. ctx%in_frame) then
    write(*,*) "ERROR: Frame begin failed"
    stop 1
  end if
  
  ! Test context-aware widget (if button_with_context is available)
  ! For now, just test that we can check if we should close
  running = .not. ui_should_close_with_context(ctx)
  
  write(*,*) "SUCCESS: Frame operations work, running =", running
  
  ! End frame
  if (ctx%in_frame) then
    call ctx%end_frame()
  end if
  
  ! Clean shutdown
  call ui_shutdown_with_context(ctx)
  
  if (ctx%initialized) then
    write(*,*) "ERROR: Shutdown did not work"
    stop 1
  end if
  
  call destroy_context(ctx)
  
  write(*,*) "SUCCESS: All context operations validated"
  write(*,*) "Documentation example patterns work correctly"
  
end program test_context_validation