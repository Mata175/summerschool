! Main solver routines for heat equation solver
module core
  use heat

contains

  ! Exchange the boundary data between MPI tasks
  subroutine exchange(field0, parallel)
    use mpi

    implicit none

    type(field), intent(inout) :: field0
    type(parallel_data), intent(in) :: parallel

    integer :: ierr

    ! Send to left, receive from right
    call mpi_sendrecv(field0%data(:, 1), field0%nx + 2, MPI_DOUBLE_PRECISION, &
         & parallel%nleft, 11, &
         & field0%data(:, field0%ny + 1), field0%nx + 2, MPI_DOUBLE_PRECISION, &
         & parallel%nright, 11, &
         & MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)

    ! Send to right, receive from left
    call mpi_sendrecv(field0%data(:, field0%ny), field0%nx + 2, MPI_DOUBLE_PRECISION, &
         & parallel%nright, 12, &
         & field0%data(:, 0), field0%nx + 2, MPI_DOUBLE_PRECISION,&
         & parallel%nleft, 12, &
         & MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)

    ! Copy the updated boundary to the device
    call update_device_boundary(field0);

  end subroutine exchange

  ! Compute one time step of temperature evolution
  ! Arguments:
  !   curr (type(field)): current temperature values
  !   prev (type(field)): values from previous time step
  !   a (real(dp)): update equation constant
  !   dt (real(dp)): time step value
  subroutine evolve(curr, prev, a, dt)

    implicit none

    type(field), target, intent(inout) :: curr, prev
    real(dp) :: a, dt
    integer :: i, j, nx, ny
    real(dp) :: dx, dy
    ! variables for memory access outside of a type
    real(dp), pointer, contiguous, dimension(:,:) :: currdata, prevdata

    ! HINT: to help the compiler do not access type components
    !       within OpenACC parallel regions
    nx = curr%nx
    ny = curr%ny
    dx = curr%dx
    dy = curr%dy
    currdata => curr%data
    prevdata => prev%data

    !$acc parallel loop private(i,j) &
    !$acc present(prevdata(0:nx+1,0:ny+1), currdata(0:nx+1,0:ny+1)) collapse(2)
    do j = 1, ny
       do i = 1, nx
          currdata(i, j) = prevdata(i, j) + a * dt * &
               & ((prevdata(i-1, j) - 2.0 * prevdata(i, j) + &
               &   prevdata(i+1, j)) / dx**2 + &
               &  (prevdata(i, j-1) - 2.0 * prevdata(i, j) + &
               &   prevdata(i, j+1)) / dy**2)
       end do
    end do
    !$end parallel loop

    ! Copy the updated boundary to the host
    !$acc update host(currdata(0:nx+1,1:1), currdata(0:nx+1,ny:ny))
  end subroutine evolve

  ! Start a data region and copy temperature fields to the device
  !   curr (type(field)): current temperature values
  !   prev (type(field)): values from previous time step
  subroutine enter_data(curr, prev)
    implicit none
    type(field), target, intent(in) :: curr, prev
    real(kind=dp), pointer, contiguous :: currdata(:,:), prevdata(:,:)

    currdata => curr%data
    prevdata => prev%data

    !$acc enter data copyin(currdata, prevdata)
  end subroutine enter_data

  ! End a data region and copy temperature fields back to the host
  !   curr (type(field)): current temperature values
  !   prev (type(field)): values from previous time step
  subroutine exit_data(curr, prev)
    implicit none
    type(field), target :: curr, prev
    real(kind=dp), pointer, contiguous :: currdata(:,:), prevdata(:,:)

    currdata => curr%data
    prevdata => prev%data

    !$acc exit data copyout(currdata, prevdata)
  end subroutine exit_data

  ! Copy a temperature field from the device to the host
  !   temperature (type(field)): temperature field
  subroutine update_host(temperature)
    implicit none
    type(field), target :: temperature
    real(kind=dp), pointer, contiguous :: tempdata(:,:)

    tempdata => temperature%data

    !$acc update host(tempdata)
  end subroutine update_host

  ! Copy the outer boundary values from the host to the device
  !   temperature (type(field)): temperature field
  subroutine update_device_boundary(temperature)
    implicit none
    type(field), target :: temperature
    real(kind=dp), pointer, contiguous :: tempdata(:,:)
    integer :: nx, ny

    tempdata => temperature%data
    nx = temperature%nx
    ny = temperature%ny

    !$acc update device(tempdata(0:nx+1,0:0), tempdata(0:nx+1,ny+1:ny+1))
  end subroutine update_device_boundary

end module core
