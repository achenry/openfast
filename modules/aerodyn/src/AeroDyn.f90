!**********************************************************************************************************************************
! LICENSING
! Copyright (C) 2015-2016  National Renewable Energy Laboratory
! Copyright (C) 2016-2021  Envision Energy USA, LTD
!
!    This file is part of AeroDyn.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!**********************************************************************************************************************************
!> AeroDyn is a time-domain aerodynamics module for horizontal-axis wind turbines.
module AeroDyn
    
   use NWTC_Library
   use AeroDyn_Types
   use AeroDyn_IO
   use BEMT
   use AirfoilInfo
   use NWTC_LAPACK
   use AeroAcoustics
   use UnsteadyAero
   use FVW
   use FVW_Subs, only: FVW_AeroOuts
   
   implicit none

   private
         

   ! ..... Public Subroutines ...................................................................................................

   public :: AD_Init                           ! Initialization routine
   public :: AD_ReInit                         ! Routine to reinitialize driver (re-initializes the states)
   public :: AD_End                            ! Ending routine (includes clean up)
   public :: AD_UpdateStates                   ! Loose coupling routine for solving for constraint states, integrating
                                               !   continuous states, and updating discrete states
   public :: AD_CalcOutput                     ! Routine for computing outputs
   public :: AD_CalcConstrStateResidual        ! Tight coupling routine for returning the constraint state residual
   
   
   PUBLIC :: AD_JacobianPInput                 ! Routine to compute the Jacobians of the output(Y), continuous - (X), discrete -
                                               !   (Xd), and constraint - state(Z) functions all with respect to the inputs(u)
   PUBLIC :: AD_JacobianPContState             ! Routine to compute the Jacobians of the output(Y), continuous - (X), discrete -
                                               !   (Xd), and constraint - state(Z) functions all with respect to the continuous
                                               !   states(x)
   PUBLIC :: AD_JacobianPDiscState             ! Routine to compute the Jacobians of the output(Y), continuous - (X), discrete -
                                               !   (Xd), and constraint - state(Z) functions all with respect to the discrete
                                               !   states(xd)
   PUBLIC :: AD_JacobianPConstrState           ! Routine to compute the Jacobians of the output(Y), continuous - (X), discrete -
                                               !   (Xd), and constraint - state(Z) functions all with respect to the constraint
                                               !   states(z)
   PUBLIC :: AD_GetOP                          !< Routine to pack the operating point values (for linearization) into arrays
   
  
contains    
!----------------------------------------------------------------------------------------------------------------------------------   
!> This subroutine sets the initialization output data structure, which contains data to be returned to the calling program (e.g.,
!! FAST or AeroDyn_Driver)   
subroutine AD_SetInitOut(p, p_AD, InputFileData, InitOut, errStat, errMsg)

   type(RotInitOutputType),       intent(  out)  :: InitOut          ! output data
   type(RotInputFile),            intent(in   )  :: InputFileData    ! input file data (for setting airfoil shape outputs)
   type(RotParameterType),        intent(in   )  :: p                ! Parameters
   type(AD_ParameterType),        intent(in   )  :: p_AD             ! Parameters
   integer(IntKi),                intent(  out)  :: errStat          ! Error status of the operation
   character(*),                  intent(  out)  :: errMsg           ! Error message if ErrStat /= ErrID_None


      ! Local variables
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'AD_SetInitOut'
   
   
   
   integer(IntKi)                               :: i, j, k, f
   integer(IntKi)                               :: NumCoords

      ! Initialize variables for this routine

   errStat = ErrID_None
   errMsg  = ""
   
   InitOut%AirDens = p%AirDens

   call AllocAry( InitOut%WriteOutputHdr, p%numOuts + p%BldNd_TotNumOuts, 'WriteOutputHdr', errStat2, errMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   
   call AllocAry( InitOut%WriteOutputUnt, p%numOuts + p%BldNd_TotNumOuts, 'WriteOutputUnt', errStat2, errMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

   if (ErrStat >= AbortErrLev) return
      
   do i=1,p%NumOuts
      InitOut%WriteOutputHdr(i) = p%OutParam(i)%Name
      InitOut%WriteOutputUnt(i) = p%OutParam(i)%Units
   end do
      
                
                
      ! Set the info in WriteOutputHdr and WriteOutputUnt
   CALL AllBldNdOuts_InitOut( InitOut, p, p_AD, InputFileData, ErrStat2, ErrMsg2 )
      call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
   
   
! set visualization data:
      ! this check is overly restrictive, but it would be a lot of work to ensure that only the *used* airfoil 
      ! tables have the same number of coordinates.
   if ( allocated(p_AD%AFI) ) then  
      
      if ( p_AD%AFI(1)%NumCoords > 0 ) then
         NumCoords = p_AD%AFI(1)%NumCoords
         do i=2,size(p_AD%AFI)
            if (p_AD%AFI(i)%NumCoords /= NumCoords) then
               call SetErrStat( ErrID_Info, 'Airfoil files do not contain the same number of x-y coordinates.', ErrStat, ErrMsg, RoutineName )
               NumCoords = -1
               exit
            end if            
         end do
            
         if (NumCoords > 0) then
            if (NumCoords < 3) then
               call SetErrStat( ErrID_Info, 'Airfoil files with NumCoords > 0 must contain at least 2 coordinates.', ErrStat, ErrMsg, RoutineName )
               return
            end if     

            allocate( InitOut%BladeShape( p%numBlades ), STAT=ErrStat2 )
            if (ErrStat2 /= 0) then
               call SetErrStat( ErrID_Info, 'Error allocationg InitOut%AD_BladeShape', ErrStat, ErrMsg, RoutineName )
               return
            end if     
            
            do k=1,p%numBlades
               call allocAry(  InitOut%BladeShape(k)%AirfoilCoords, 2, NumCoords-1, InputFileData%BladeProps(k)%NumBlNds, 'AirfoilCoords', ErrStat2, ErrMsg2)
                  call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
                  if (ErrStat >= AbortErrLev) return
                  
               do j=1,InputFileData%BladeProps(k)%NumBlNds
                  f = InputFileData%BladeProps(k)%BlAFID(j)
                  
                  do i=1,NumCoords-1                                                     
                     InitOut%BladeShape(k)%AirfoilCoords(1,i,j) = InputFileData%BladeProps(k)%BlChord(j)*( p_AD%AFI(f)%Y_Coord(i+1) - p_AD%AFI(f)%Y_Coord(1) )
                     InitOut%BladeShape(k)%AirfoilCoords(2,i,j) = InputFileData%BladeProps(k)%BlChord(j)*( p_AD%AFI(f)%X_Coord(i+1) - p_AD%AFI(f)%X_Coord(1) )
                  end do                  
               end do
                                 
            end do
            
         end if                  
      end if
      
   end if
   
   
   ! set blade properties data  ! bjj: I would probably do a move_alloc() at the end of the init routine rather than make a copy like this.... 
   ALLOCATE(InitOut%BladeProps(p%numBlades), STAT = ErrStat2)
   IF (ErrStat2 /= 0) THEN
      CALL SetErrStat(ErrID_Fatal,"Error allocating memory for BladeProps.", ErrStat, ErrMsg, RoutineName)
      RETURN
   END IF
   do k=1,p%numBlades
      ! allocate space and copy blade data:
      CALL AD_CopyBladePropsType(InputFileData%BladeProps(k), InitOut%BladeProps(k), MESH_NEWCOPY, ErrStat2, ErrMsg2)
      CALL SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
   end do

   !Tower data
   IF ( p%NumTwrNds > 0 ) THEN
      ALLOCATE(InitOut%TwrElev(p%NumTwrNds), STAT = ErrStat2)
      IF (ErrStat2 /= 0) THEN
         CALL SetErrStat(ErrID_Fatal,"Error allocating memory for TwrElev.", ErrStat, ErrMsg, RoutineName)
         RETURN
      END IF
      InitOut%TwrElev(:) = InputFileData%TwrElev(:)

      ALLOCATE(InitOut%TwrDiam(p%NumTwrNds), STAT = ErrStat2)
      IF (ErrStat2 /= 0) THEN
         CALL SetErrStat(ErrID_Fatal,"Error allocating memory for TwrDiam.", ErrStat, ErrMsg, RoutineName)
         RETURN
      END IF   
      InitOut%TwrDiam(:) = p%TwrDiam(:)
   END IF  
   
end subroutine AD_SetInitOut
!----------------------------------------------------------------------------------------------------------------------------------   
!> This routine is called at the start of the simulation to perform initialization steps.
!! The parameters are set here and not changed during the simulation.
!! The initial states and initial guess for the input are defined.
subroutine AD_Init( InitInp, u, p, x, xd, z, OtherState, y, m, Interval, InitOut, ErrStat, ErrMsg )
!..................................................................................................................................

   type(AD_InitInputType),       intent(in   ) :: InitInp       !< Input data for initialization routine
   type(AD_InputType),           intent(  out) :: u             !< An initial guess for the input; input mesh must be defined
   type(AD_ParameterType),       intent(  out) :: p             !< Parameters
   type(AD_ContinuousStateType), intent(  out) :: x             !< Initial continuous states
   type(AD_DiscreteStateType),   intent(  out) :: xd            !< Initial discrete states
   type(AD_ConstraintStateType), intent(  out) :: z             !< Initial guess of the constraint states
   type(AD_OtherStateType),      intent(  out) :: OtherState    !< Initial other states
   type(AD_OutputType),          intent(  out) :: y             !< Initial system outputs (outputs are not calculated;
                                                                !!   only the output mesh is initialized)
   type(AD_MiscVarType),         intent(  out) :: m             !< Initial misc/optimization variables
   real(DbKi),                   intent(inout) :: interval      !< Coupling interval in seconds: the rate that
                                                                !!   (1) AD_UpdateStates() is called in loose coupling &
                                                                !!   (2) AD_UpdateDiscState() is called in tight coupling.
                                                                !!   Input is the suggested time from the glue code;
                                                                !!   Output is the actual coupling interval that will be used
                                                                !!   by the glue code.
   type(AD_InitOutputType),      intent(  out) :: InitOut       !< Output for initialization routine
   integer(IntKi),               intent(  out) :: errStat       !< Error status of the operation
   character(*),                 intent(  out) :: errMsg        !< Error message if ErrStat /= ErrID_None
   

      ! Local variables
   integer(IntKi)                              :: i             ! loop counter
   integer(IntKi)                              :: iR            ! loop on rotors
   
   integer(IntKi)                              :: errStat2      ! temporary error status of the operation
   character(ErrMsgLen)                        :: errMsg2       ! temporary error message 
      
   type(FileInfoType)                          :: FileInfo_In   !< The derived type for holding the full input file for parsing -- we may pass this in the future
   type(AD_InputFile)                          :: InputFileData ! Data stored in the module's input file after parsing
   character(1024)                             :: PriPath       !< Primary path
   character(1024)                             :: EchoFileName
   integer(IntKi)                              :: UnEcho        ! Unit number for the echo file
   integer(IntKi)                              :: nRotors       ! Number of rotors
   integer(IntKi), allocatable, dimension(:)   :: NumBlades     ! Number of blades per rotor

   character(*), parameter                     :: RoutineName = 'AD_Init'
   
   
      ! Initialize variables for this routine

   errStat = ErrID_None
   errMsg  = ""
   UnEcho  = -1

      ! Initialize the NWTC Subroutine Library

   call NWTC_Init( EchoLibVer=.FALSE. )

      ! Display the module information

   call DispNVD( AD_Ver )
   

      ! Allocate rotors data types

   nRotors = size(InitInp%rotors)
   allocate(x%rotors(nRotors), xd%rotors(nRotors), z%rotors(nRotors), OtherState%rotors(nRotors), stat=errStat) 
   if (errStat/=0) call SetErrStat( ErrID_Fatal, 'Allocating rotor states', errStat, errMsg, RoutineName )
   allocate(u%rotors(nRotors), y%rotors(nRotors), InitOut%rotors(nRotors), InputFileData%rotors(nRotors), stat=errStat) 
   if (errStat/=0) call SetErrStat( ErrID_Fatal, 'Allocating rotor input/outputs', errStat, errMsg, RoutineName )
   allocate(p%rotors(nRotors), m%rotors(nRotors), stat=errStat) 
   if (errStat/=0) call SetErrStat( ErrID_Fatal, 'Allocating rotor params/misc', errStat, errMsg, RoutineName )
   if (errStat/=ErrID_None) then
      call Cleanup()
      return
   end if



      ! set a few parameters needed while reading the input file
   allocate(NumBlades(nRotors))
   do iR = 1, nRotors
      call ValidateNumBlades( InitInp%rotors(iR)%NumBlades, ErrStat2, ErrMsg2 )
      if (Failed()) return;
      NumBlades(iR)          = InitInp%rotors(iR)%NumBlades
      p%rotors(iR)%NumBlades = InitInp%rotors(iR)%NumBlades
      if (nRotors > 1) then
         p%rotors(iR)%RootName  = TRIM(InitInp%RootName)//'.AD.R'//trim(num2lstr(iR))
      else
         p%rotors(iR)%RootName  = TRIM(InitInp%RootName)//'.AD'
      endif
   enddo
   p%RootName  = TRIM(InitInp%RootName)//'.AD'

   CALL GetPath( InitInp%InputFile, PriPath )     ! Input files will be relative to the path where the primary input file is located.

      ! -----------------------------------------------------------------
      ! Read the primary AeroDyn input file, or copy from passed input
   if (InitInp%UsePrimaryInputFile) then
      ! Read the entire input file, minus any comment lines, into the FileInfo_In
      ! data structure in memory for further processing.
      call ProcessComFile( InitInp%InputFile, FileInfo_In, ErrStat2, ErrMsg2 )
   else
      call NWTC_Library_CopyFileInfoType( InitInp%PassedPrimaryInputData, FileInfo_In, MESH_NEWCOPY, ErrStat2, ErrMsg2 )
   endif
   if (Failed()) return;

   ! For diagnostic purposes, the following can be used to display the contents
   ! of the FileInfo_In data structure.
   ! call Print_FileInfo_Struct( CU, FileInfo_In ) ! CU is the screen -- different number on different systems.

      !  Parse the FileInfo_In structure of data from the inputfile into the InitInp%InputFile structure
   CALL ParsePrimaryFileInfo( PriPath, InitInp, InitInp%InputFile, p%RootName, NumBlades, interval, FileInfo_In, InputFileData, UnEcho, ErrStat2, ErrMsg2 )
      if (Failed()) return;

      ! -----------------------------------------------------------------
      ! Read the AeroDyn blade files, or copy from passed input
!FIXME: add handling for passing of blade files and other types of files.
   call ReadInputFiles( InitInp%InputFile, InputFileData, interval, p%RootName, NumBlades, UnEcho, ErrStat2, ErrMsg2 )
      if (Failed()) return;

      ! Validate the inputs
   call ValidateInputData( InitInp, InputFileData, NumBlades, ErrStat2, ErrMsg2 )
   if (Failed()) return;
      
      !............................................................................................
      ! Define parameters
      !............................................................................................
      
      ! Initialize AFI module (read Airfoil tables)
   call Init_AFIparams( InputFileData, p%AFI, UnEcho, ErrStat2, ErrMsg2 )
   if (Failed()) return;
         
      
      ! set the rest of the parameters
   do iR = 1, nRotors
      p%rotors(iR)%AeroProjMod = InitInp%rotors(iR)%AeroProjMod
      call SetParameters( InitInp, InputFileData, InputFileData%rotors(iR), p%rotors(iR), p, ErrStat2, ErrMsg2 )
      if (Failed()) return;
   enddo
  
      !............................................................................................
      ! Define and initialize inputs here 
      !............................................................................................
   do iR = 1, nRotors
      call Init_u( u%rotors(iR), p%rotors(iR), p, InputFileData%rotors(iR), InitInp%rotors(iR), errStat2, errMsg2 ) 
      if (Failed()) return;
   enddo


      !............................................................................................
      ! Initialize the BEMT module (also sets other variables for sub module)
      !............................................................................................
      
      ! initialize BEMT after setting parameters and inputs because we are going to use the already-
      ! calculated node positions from the input meshes
      
   if (p%WakeMod /= WakeMod_FVW) then
      do iR = 1, nRotors
         call Init_BEMTmodule( InputFileData, InputFileData%rotors(iR), u%rotors(iR), m%rotors(iR)%BEMT_u(1), p%rotors(iR), p, x%rotors(iR)%BEMT, xd%rotors(iR)%BEMT, z%rotors(iR)%BEMT, &
                                 OtherState%rotors(iR)%BEMT, m%rotors(iR)%BEMT_y, m%rotors(iR)%BEMT, ErrStat2, ErrMsg2 )
         if (Failed()) return;

         call BEMT_CopyInput( m%rotors(iR)%BEMT_u(1), m%rotors(iR)%BEMT_u(2), MESH_NEWCOPY, ErrStat2, ErrMsg2 )
            call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
    
            
            !............................................................................................
            ! Initialize the AeroAcoustics Module if the CompAA flag is set
            !............................................................................................
         if (p%rotors(iR)%CompAA) then
            call Init_AAmodule( InitInp%rotors(iR), InputFileData, InputFileData%rotors(iR), u%rotors(iR), m%rotors(iR)%AA_u, p%rotors(iR), p, x%rotors(iR)%AA, xd%rotors(iR)%AA, z%rotors(iR)%AA, OtherState%rotors(iR)%AA, m%rotors(iR)%AA_y, m%rotors(iR)%AA, ErrStat2, ErrMsg2 )
            if (Failed()) return;
         end if   
      enddo

   else ! if (p%WakeMod == WakeMod_FVW) then

      !-------------------------------------------------------------------------------------------------
      ! Initialize FVW module if it is used
      !-------------------------------------------------------------------------------------------------
      ! Unfortunately we do not know the interpolation order used by OpenFAST glue code at this point,
      ! so we can't size things exactly.  This means that we either must size too big here, or we must
      ! resize in the FVW code at the first CalcOutput call.  This is a bit problematic for efficiency
      ! but not a complete deal-breaker.
   
      if (.not. allocated(m%FVW_u))   Allocate(m%FVW_u(3))  !size(u)))
      call Init_OLAF( InputFileData, u, m%FVW_u(1), p, x%FVW, xd%FVW, z%FVW, OtherState%FVW, m, ErrStat2, ErrMsg2 )
      if (Failed()) return;
         ! populate the rest of the FVW_u so that extrap-interp will work
      do i=2,3 !size(u)
         call FVW_CopyInput( m%FVW_u(1), m%FVW_u(i), MESH_NEWCOPY, ErrStat2, ErrMsg2 )
         if (Failed()) return;
      enddo
   endif
    
 
      !............................................................................................
      ! Define outputs here
      !............................................................................................
   do iR = 1, nRotors
      call Init_y(y%rotors(iR), u%rotors(iR), p%rotors(iR), errStat2, errMsg2) ! do this after input meshes have been initialized
      if (Failed()) return;
   enddo
   
   
      !............................................................................................
      ! Initialize states and misc vars
      !............................................................................................
      
      ! many states are in the BEMT module, which were initialized in BEMT_Init()
      
   do iR = 1, nRotors
      call Init_MiscVars(m%rotors(iR), p%rotors(iR), u%rotors(iR), y%rotors(iR), errStat2, errMsg2)
      if (Failed()) return;
   enddo
      
      !............................................................................................
      ! Initialize other states
      !............................................................................................
      ! The wake from FVW is stored in other states.  This may not be the best place to put it!
   call Init_OtherStates(m, p, OtherState, errStat2, errMsg2)
   if (Failed()) return;

      !............................................................................................
      ! Define initialization output here
      !............................................................................................
   InitOut%Ver = AD_Ver
   do iR = 1, nRotors
      call AD_SetInitOut(p%rotors(iR), p, InputFileData%rotors(iR), InitOut%rotors(iR), errStat2, errMsg2)
      if (Failed()) return;
   enddo
   
      ! after setting InitOut variables, we really don't need the airfoil coordinates taking up
      ! space in AeroDyn
   if ( allocated(p%AFI) ) then  
      do i=1,size(p%AFI)
         if (allocated(p%AFI(i)%X_Coord)) deallocate( p%AFI(i)%X_Coord) 
         if (allocated(p%AFI(i)%Y_Coord)) deallocate( p%AFI(i)%Y_Coord) 
      end do
   end if
   
      !............................................................................................
      ! Initialize Jacobian:
      !............................................................................................
   if (InitInp%Linearize) then      
      do iR = 1, nRotors
         call Init_Jacobian(InputFileData%rotors(iR), p%rotors(iR), p, u%rotors(iR), y%rotors(iR), m%rotors(iR), InitOut%rotors(iR), errStat2, errMsg2)
         if (Failed()) return;
      enddo
   end if
   
      !............................................................................................
      ! Print the summary file if requested:
      !............................................................................................
   if (InputFileData%SumPrint) then
      do iR = 1, nRotors
         call AD_PrintSum( InputFileData, p%rotors(iR), p, u, y, ErrStat2, ErrMsg2 )
         if (Failed()) return;
      enddo
   end if
      
      !............................................................................................
      ! If you want to choose your own rate instead of using what the glue code suggests, tell the glue code the rate at which
      !   this module must be called here:
      !............................................................................................

   Interval = p%DT


   call Cleanup() 
      
contains
   logical function Failed()
      CALL SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
      Failed = ErrStat >= AbortErrLev
      if (Failed)    call Cleanup()
   end function Failed
   subroutine Cleanup()

      CALL AD_DestroyInputFile( InputFileData, ErrStat2, ErrMsg2 )
      CALL NWTC_Library_Destroyfileinfotype(FileInfo_In, ErrStat2, ErrMsg2)
      IF ( UnEcho > 0 ) CLOSE( UnEcho )
      
   end subroutine Cleanup

end subroutine AD_Init
!----------------------------------------------------------------------------------------------------------------------------------   
!> This subroutine reinitializes BEMT and UA, assuming that we will start the simulation over again, with only the inputs being different.
!! This allows us to bypass reading input files and allocating arrays because p is already set.
subroutine AD_ReInit(p, x, xd, z, OtherState, m, Interval, ErrStat, ErrMsg )   

   type(AD_ParameterType),       intent(in   ) :: p             !< Parameters
   type(AD_ContinuousStateType), intent(inout) :: x             !< Initial continuous states
   type(AD_DiscreteStateType),   intent(inout) :: xd            !< Initial discrete states
   type(AD_ConstraintStateType), intent(inout) :: z             !< Initial guess of the constraint states
   type(AD_OtherStateType),      intent(inout) :: OtherState    !< Initial other states
   type(AD_MiscVarType),         intent(inout) :: m             !< Initial misc/optimization variables
   real(DbKi),                   intent(in   ) :: interval      !< Coupling interval in seconds: the rate that
                                                                !!   (1) AD_UpdateStates() is called in loose coupling &
                                                                !!   (2) AD_UpdateDiscState() is called in tight coupling.
                                                                !!   Input is the suggested time from the glue code;
                                                                !!   Output is the actual coupling interval that will be used
                                                                !!   by the glue code.
   integer(IntKi),               intent(  out) :: errStat       !< Error status of the operation
   character(*),                 intent(  out) :: errMsg        !< Error message if ErrStat /= ErrID_None

   integer(IntKi)                              :: iR            ! loop on rotors
   integer(IntKi)                              :: ErrStat2
   character(ErrMsgLen)                        :: ErrMsg2
   character(*), parameter                     :: RoutineName = 'AD_ReInit'

   
   ErrStat = ErrID_None
   ErrMsg = ''
   
   if ( .not. EqualRealNos(p%DT, interval) ) then
      call SetErrStat( ErrID_Fatal, 'When AD is reinitialized, DT must not change.', ErrStat, ErrMsg, RoutineName )
      return
      ! we could get around this by figuring out what needs to change when we modify the dt parameter... probably just some unused-parameters
      ! and the UA filter
   end if
      
   if (p%WakeMod /= WakeMod_FVW) then
      do IR=1, size(p%rotors)
         call BEMT_ReInit(p%rotors(iR)%BEMT,x%rotors(iR)%BEMT,xd%rotors(iR)%BEMT,z%rotors(iR)%BEMT,OtherState%rotors(iR)%BEMT,m%rotors(iR)%BEMT,ErrStat,ErrMsg)

         if (p%UA_Flag) then
            call UA_ReInit( p%rotors(iR)%BEMT%UA, x%rotors(iR)%BEMT%UA, xd%rotors(iR)%BEMT%UA, OtherState%rotors(iR)%BEMT%UA, m%rotors(iR)%BEMT%UA, ErrStat2, ErrMsg2 )
               call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         end if
      enddo
   end if

      
end subroutine AD_ReInit
!----------------------------------------------------------------------------------------------------------------------------------   
!> This routine initializes (allocates) the misc variables for use during the simulation.
subroutine Init_MiscVars(m, p, u, y, errStat, errMsg)
   type(RotMiscVarType),          intent(inout)  :: m                !< misc/optimization data (not defined in submodules)
   type(RotParameterType),        intent(in   )  :: p                !< Parameters
   type(RotInputType),            intent(inout)  :: u                !< input for HubMotion mesh (create sibling mesh here)
   type(RotOutputType),           intent(in   )  :: y                !< output (create mapping between output and otherstate mesh here)
   integer(IntKi),                intent(  out)  :: errStat          !< Error status of the operation
   character(*),                  intent(  out)  :: errMsg           !< Error message if ErrStat /= ErrID_None


      ! Local variables
   integer(intKi)                               :: k
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'Init_MiscVars'

      ! Initialize variables for this routine

   errStat = ErrID_None
   errMsg  = ""
   
   call AllocAry( m%DisturbedInflow, 3_IntKi, p%NumBlNds, p%numBlades, 'OtherState%DisturbedInflow', ErrStat2, ErrMsg2 ) ! must be same size as u%InflowOnBlade
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%WithoutSweepPitchTwist, 3_IntKi, 3_IntKi, p%NumBlNds, p%numBlades, 'OtherState%WithoutSweepPitchTwist', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
     
   call allocAry( m%SigmaCavit, p%NumBlNds, p%numBlades, 'm%SigmaCavit', errStat2, errMsg2); call setErrStat(errStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call allocAry( m%SigmaCavitCrit, p%NumBlNds, p%numBlades, 'm%SigmaCavitCrit', errStat2, errMsg2); call setErrStat(errStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call allocAry( m%CavitWarnSet, p%NumBlNds, p%numBlades, 'm%CavitWarnSet', errStat2, errMsg2); call setErrStat(errStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   m%SigmaCavit     = 0.0_ReKi      !Init to zero for output files in case a cavit check isnt done but output is requested 
   m%SigmaCavitCrit = 0.0_ReKi
   m%CavitWarnSet   = .false.
         ! arrays for output
   allocate( m%AllOuts(0:MaxOutPts), STAT=ErrStat2 ) ! allocate starting at zero to account for invalid output channels
      if (ErrStat2 /= 0) then
         call SetErrStat( ErrID_Fatal, "Error allocating AllOuts.", errStat, errMsg, RoutineName )
         return
      end if
   m%AllOuts = 0.0_ReKi
 
      ! save these tower calculations for output:
   call AllocAry( m%W_Twr, p%NumTwrNds, 'm%W_Twr', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%X_Twr, p%NumTwrNds, 'm%X_Twr', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%Y_Twr, p%NumTwrNds, 'm%Y_Twr', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      ! save blade calculations for output:
if (p%TwrPotent /= TwrPotent_none .or. p%TwrShadow /= TwrShadow_none) then
   call AllocAry( m%TwrClrnc, p%NumBlNds, p%NumBlades, 'm%TwrClrnc', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
end if            
   call AllocAry( m%Curve, p%NumBlNds, p%NumBlades, 'm%Curve', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )            
   call AllocAry( m%X, p%NumBlNds, p%NumBlades, 'm%X', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%Y, p%NumBlNds, p%NumBlades, 'm%Y', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%M, p%NumBlNds, p%NumBlades, 'm%M', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( m%hub_theta_x_root, p%NumBlades, 'm%hub_theta_x_root', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      ! mesh mapping data for integrating load over entire rotor:
   allocate( m%B_L_2_H_P(p%NumBlades), Stat = ErrStat2)
      if (ErrStat2 /= 0) then
         call SetErrStat( ErrID_Fatal, "Error allocating B_L_2_H_P mapping structure.", errStat, errMsg, RoutineName )
         return
      end if

   call MeshCopy (  SrcMesh  = u%HubMotion        &
                  , DestMesh = m%HubLoad          &
                  , CtrlCode = MESH_SIBLING       &
                  , IOS      = COMPONENT_OUTPUT   &
                  , force    = .TRUE.             &
                  , moment   = .TRUE.             &
                  , ErrStat  = ErrStat2           &
                  , ErrMess  = ErrMsg2            )
   
      call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName ) 
      if (ErrStat >= AbortErrLev) RETURN         
   
   do k=1,p%NumBlades
      CALL MeshMapCreate( y%BladeLoad(k), m%HubLoad, m%B_L_2_H_P(k), ErrStat2, ErrMsg2 )
         CALL SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName//':B_L_2_H_P('//TRIM(Num2LStr(K))//')' )
   end do
   
   if (ErrStat >= AbortErrLev) RETURN
    
   ! Mesh mapping data for integrating load over entire blade:
   allocate( m%B_L_2_R_P(p%NumBlades), Stat = ErrStat2)
      if (ErrStat2 /= 0) then
         call SetErrStat( ErrID_Fatal, "Error allocating B_L_2_R_P mapping structure.", errStat, errMsg, RoutineName )
         return
      end if
   allocate( m%BladeRootLoad(p%NumBlades), Stat = ErrStat2)
      if (ErrStat2 /= 0) then
         call SetErrStat( ErrID_Fatal, "Error allocating BladeRootLoad mesh array.", errStat, errMsg, RoutineName )
         return
      end if    

   do k=1,p%NumBlades
      call MeshCopy (  SrcMesh  = u%BladeRootMotion(k)  &
                     , DestMesh = m%BladeRootLoad(k)    &
                     , CtrlCode = MESH_SIBLING          &
                     , IOS      = COMPONENT_OUTPUT      &
                     , force    = .TRUE.                &
                     , moment   = .TRUE.                &
                     , ErrStat  = ErrStat2              &
                     , ErrMess  = ErrMsg2               )
   
         call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )          
   end do  !k=blades
   
   if (ErrStat >= AbortErrLev) RETURN
   
   do k=1,p%NumBlades
      CALL MeshMapCreate( y%BladeLoad(k), m%BladeRootLoad(k), m%B_L_2_R_P(k), ErrStat2, ErrMsg2 )
         CALL SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName//':B_L_2_R_P('//TRIM(Num2LStr(K))//')' )
   end do  !k=blades
   
   if (ErrStat >= AbortErrLev) RETURN
   
   ! 
   if (p%NumTwrNds > 0) then
      m%W_Twr = 0.0_ReKi
      m%X_Twr = 0.0_ReKi
      m%Y_Twr = 0.0_ReKi
   end if
   
   
   
end subroutine Init_MiscVars
!----------------------------------------------------------------------------------------------------------------------------------   
!> This routine initializes (allocates) the misc variables for use during the simulation.
subroutine Init_OtherStates(m, p, OtherState, errStat, errMsg)
   type(AD_MiscVarType),          intent(in   )  :: m                !< misc/optimization data (not defined in submodules)
   type(AD_ParameterType),        intent(in   )  :: p                !< Parameters
   type(AD_OtherStateType),       intent(inout)  :: OtherState       !< Discrete states
   integer(IntKi),                intent(  out)  :: errStat          !< Error status of the operation
   character(*),                  intent(  out)  :: errMsg           !< Error message if ErrStat /= ErrID_None
      ! Local variables
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'Init_OtherStates'

   errStat = ErrID_None
   errMsg  = ""
   ! store Wake positions in otherstates.  This may not be the best location
   if (allocated(m%FVW%r_wind)) then
      call AllocAry( OtherState%WakeLocationPoints, 3_IntKi, size(m%FVW%r_wind,DIM=2), ' OtherState%WakeLocationPoints', ErrStat2, ErrMsg2 ) ! must be same size as m%r_wind from FVW
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      OtherState%WakeLocationPoints = m%FVW%r_wind
   endif
end subroutine Init_OtherStates
!----------------------------------------------------------------------------------------------------------------------------------   
!> This routine initializes AeroDyn meshes and output array variables for use during the simulation.
subroutine Init_y(y, u, p, errStat, errMsg)
   type(RotOutputType),           intent(  out)  :: y               !< Module outputs
   type(RotInputType),            intent(inout)  :: u               !< Module inputs -- intent(out) because of mesh sibling copy
   type(RotParameterType),        intent(in   )  :: p               !< Parameters
   integer(IntKi),                intent(  out)  :: errStat         !< Error status of the operation
   character(*),                  intent(  out)  :: errMsg          !< Error message if ErrStat /= ErrID_None


      ! Local variables
   integer(intKi)                               :: k                 ! loop counter for blades
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'Init_y'

      ! Initialize variables for this routine

   errStat = ErrID_None
   errMsg  = ""
   
         
   if (p%TwrAero) then
            
      call MeshCopy ( SrcMesh  = u%TowerMotion    &
                    , DestMesh = y%TowerLoad      &
                    , CtrlCode = MESH_SIBLING     &
                    , IOS      = COMPONENT_OUTPUT &
                    , force    = .TRUE.           &
                    , moment   = .TRUE.           &
                    , ErrStat  = ErrStat2         &
                    , ErrMess  = ErrMsg2          )
   
         call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName ) 
         if (ErrStat >= AbortErrLev) RETURN         
         
         !y%TowerLoad%force = 0.0_ReKi  ! shouldn't have to initialize this
         !y%TowerLoad%moment= 0.0_ReKi  ! shouldn't have to initialize this
   else
      y%TowerLoad%nnodes = 0
   end if

      call MeshCopy ( SrcMesh  = u%NacelleMotion  &
                    , DestMesh = y%NacelleLoad    &
                    , CtrlCode = MESH_SIBLING     &
                    , IOS      = COMPONENT_OUTPUT &
                    , force    = .TRUE.           &
                    , moment   = .TRUE.           &
                    , ErrStat  = ErrStat2         &
                    , ErrMess  = ErrMsg2          )
   
         call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName ) 
         if (ErrStat >= AbortErrLev) RETURN         
         
   allocate( y%BladeLoad(p%numBlades), stat=ErrStat2 )
   if (errStat2 /= 0) then
      call SetErrStat( ErrID_Fatal, 'Error allocating y%BladeLoad.', ErrStat, ErrMsg, RoutineName )      
      return
   end if
   

   do k = 1, p%numBlades
   
      call MeshCopy ( SrcMesh  = u%BladeMotion(k) &
                    , DestMesh = y%BladeLoad(k)   &
                    , CtrlCode = MESH_SIBLING     &
                    , IOS      = COMPONENT_OUTPUT &
                    , force    = .TRUE.           &
                    , moment   = .TRUE.           &
                    , ErrStat  = ErrStat2         &
                    , ErrMess  = ErrMsg2          )
   
         call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName ) 
                           
   end do

   call AllocAry( y%WriteOutput, p%numOuts + p%BldNd_TotNumOuts, 'WriteOutput', errStat2, errMsg2 )
      call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
   if (ErrStat >= AbortErrLev) RETURN      
   
   
   
end subroutine Init_y
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine initializes AeroDyn meshes and input array variables for use during the simulation.
subroutine Init_u( u, p, p_AD, InputFileData, InitInp, errStat, errMsg )
!..................................................................................................................................

   type(RotInputType),           intent(  out)  :: u                 !< Input data
   type(RotParameterType),       intent(in   )  :: p                 !< Parameters
   type(AD_ParameterType),       intent(in   )  :: p_AD              !< Parameters
   type(RotInputFile),           intent(in   )  :: InputFileData     !< Data stored in the module's input file
   type(RotInitInputType),       intent(in   )  :: InitInp           !< Input data for AD initialization routine
   integer(IntKi),               intent(  out)  :: errStat           !< Error status of the operation
   character(*),                 intent(  out)  :: errMsg            !< Error message if ErrStat /= ErrID_None


      ! Local variables
   real(reKi)                                   :: position(3)       ! node reference position
   real(reKi)                                   :: positionL(3)      ! node local position
   real(R8Ki)                                   :: theta(3)          ! Euler angles
   real(R8Ki)                                   :: orientation(3,3)  ! node reference orientation
   real(R8Ki)                                   :: orientationL(3,3) ! node local orientation
   
   integer(intKi)                               :: j                 ! counter for nodes
   integer(intKi)                               :: k                 ! counter for blades
   
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'Init_u'

      ! Initialize variables for this routine

   ErrStat = ErrID_None
   ErrMsg  = ""


      ! Arrays for InflowWind inputs:
   
   call AllocAry( u%InflowOnBlade, 3_IntKi, p%NumBlNds, p%numBlades, 'u%InflowOnBlade', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( u%InflowOnTower, 3_IntKi, p%NumTwrNds, 'u%InflowOnTower', ErrStat2, ErrMsg2 ) ! could be size zero
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

   call AllocAry( u%UserProp, p%NumBlNds, p%numBlades, 'u%UserProp', ErrStat2, ErrMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      
   if (errStat >= AbortErrLev) return      
      
   u%InflowOnBlade = 0.0_ReKi
   u%UserProp      = 0.0_ReKi
   u%InflowOnNacelle = 0.0_ReKi
   
      ! Meshes for motion inputs (ElastoDyn and/or BeamDyn)
         !................
         ! tower
         !................
   if (p%NumTwrNds > 0) then
      
      u%InflowOnTower = 0.0_ReKi 
      
      call MeshCreate ( BlankMesh = u%TowerMotion   &
                       ,IOS       = COMPONENT_INPUT &
                       ,Nnodes    = p%NumTwrNds     &
                       ,ErrStat   = ErrStat2        &
                       ,ErrMess   = ErrMsg2         &
                       ,Orientation     = .true.    &
                       ,TranslationDisp = .true.    &
                       ,TranslationVel  = .true.    &
                      )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      if (errStat >= AbortErrLev) return
            
         ! set node initial position/orientation
      position = 0.0_ReKi
      do j=1,p%NumTwrNds         
         position(3) = InputFileData%TwrElev(j)
         
         call MeshPositionNode(u%TowerMotion, j, position, errStat2, errMsg2)  ! orientation is identity by default
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      end do !j
         
         ! create line2 elements
      do j=1,p%NumTwrNds-1
         call MeshConstructElement( u%TowerMotion, ELEMENT_LINE2, errStat2, errMsg2, p1=j, p2=j+1 )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      end do !j
            
      call MeshCommit(u%TowerMotion, errStat2, errMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
            
      if (errStat >= AbortErrLev) return

      
      u%TowerMotion%Orientation     = u%TowerMotion%RefOrientation
      u%TowerMotion%TranslationDisp = 0.0_R8Ki
      u%TowerMotion%TranslationVel  = 0.0_ReKi
      
   end if ! we compute tower loads
   
      !................
      ! hub
      !................
   
   call MeshCreate ( BlankMesh  = u%HubMotion     &
                     ,IOS       = COMPONENT_INPUT &
                     ,Nnodes    = 1               &
                     ,ErrStat   = ErrStat2        &
                     ,ErrMess   = ErrMsg2         &
                     ,Orientation     = .true.    &
                     ,TranslationDisp = .true.    &
                     ,RotationVel     = .true.    &
                     )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

   if (errStat >= AbortErrLev) return
                     
   call MeshPositionNode(u%HubMotion, 1, InitInp%HubPosition, errStat2, errMsg2, InitInp%HubOrientation)
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
         
   call MeshConstructElement( u%HubMotion, ELEMENT_POINT, errStat2, errMsg2, p1=1 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
            
   call MeshCommit(u%HubMotion, errStat2, errMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName//':HubMotion' )
            
   if (errStat >= AbortErrLev) return

         
   u%HubMotion%Orientation     = u%HubMotion%RefOrientation
   u%HubMotion%TranslationDisp = 0.0_R8Ki
   u%HubMotion%RotationVel     = 0.0_ReKi   
      
   
      !................
      ! blade roots
      !................
         
   allocate( u%BladeRootMotion(p%NumBlades), STAT = ErrStat2 )
   if (ErrStat2 /= 0) then
      call SetErrStat( ErrID_Fatal, 'Error allocating u%BladeRootMotion array.', ErrStat, ErrMsg, RoutineName )
      return
   end if      
      
   do k=1,p%NumBlades
      call MeshCreate ( BlankMesh = u%BladeRootMotion(k)                  &
                        ,IOS       = COMPONENT_INPUT                       &
                        ,Nnodes    = 1                                     &
                        ,ErrStat   = ErrStat2                              &
                        ,ErrMess   = ErrMsg2                               &
                        ,Orientation     = .true.                          &
                        ,TranslationDisp=.true., TranslationVel=.true.     & 
                        ,RotationVel=.true., TranslationAcc=.true., RotationAcc=.true. &
                        )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      if (errStat >= AbortErrLev) return
            
      call MeshPositionNode(u%BladeRootMotion(k), 1, InitInp%BladeRootPosition(:,k), errStat2, errMsg2, InitInp%BladeRootOrientation(:,:,k))
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
                     
      call MeshConstructElement( u%BladeRootMotion(k), ELEMENT_POINT, errStat2, errMsg2, p1=1 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
            
      call MeshCommit(u%BladeRootMotion(k), errStat2, errMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName//':BladeRootMotion' )
            
      if (errStat >= AbortErrLev) return

      
      u%BladeRootMotion(k)%Orientation     = u%BladeRootMotion(k)%RefOrientation
   
   end do !k=numBlades      
      
      
      !................
      ! blades
      !................
   
   allocate( u%BladeMotion(p%NumBlades), STAT = ErrStat2 )
   if (ErrStat2 /= 0) then
      call SetErrStat( ErrID_Fatal, 'Error allocating u%BladeMotion array.', ErrStat, ErrMsg, RoutineName )
      return
   end if
      
   do k=1,p%NumBlades
      call MeshCreate ( BlankMesh = u%BladeMotion(k)                     &
                        ,IOS       = COMPONENT_INPUT                      &
                        ,Nnodes    = InputFileData%BladeProps(k)%NumBlNds &
                        ,ErrStat   = ErrStat2                             &
                        ,ErrMess   = ErrMsg2                              &
                        ,Orientation     = .true.                         &
                        ,TranslationDisp = .true.                         &
                        ,TranslationVel  = .true.                         &
                        ,RotationVel     = .true.                         &
                        ,TranslationAcc  = .true.                         &
                        )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      if (errStat >= AbortErrLev) return
            
                        
      do j=1,InputFileData%BladeProps(k)%NumBlNds

            ! reference position of the jth node in the kth blade, relative to the root in the local blade coordinate system:
         positionL(1) = InputFileData%BladeProps(k)%BlCrvAC(j)
         positionL(2) = InputFileData%BladeProps(k)%BlSwpAC(j)
         positionL(3) = InputFileData%BladeProps(k)%BlSpn(  j)
            
            ! reference position of the jth node in the kth blade:
         position = u%BladeRootMotion(k)%Position(:,1) + matmul(positionL,u%BladeRootMotion(k)%RefOrientation(:,:,1))  ! note that because positionL is a 1-D array, we're doing the transpose of matmul(transpose(u%BladeRootMotion(k)%RefOrientation),positionL)

            
            ! reference orientation of the jth node in the kth blade, relative to the root in the local blade coordinate system:
         theta(1)     =  0.0_R8Ki
         theta(2)     =  InputFileData%BladeProps(k)%BlCrvAng(j)
         theta(3)     = -InputFileData%BladeProps(k)%BlTwist( j)            
         orientationL = EulerConstruct( theta )
                                 
            ! reference orientation of the jth node in the kth blade
         orientation = matmul( orientationL, u%BladeRootMotion(k)%RefOrientation(:,:,1) )

            
         call MeshPositionNode(u%BladeMotion(k), j, position, errStat2, errMsg2, orientation)
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
               
      end do ! j=blade nodes
         
         ! create line2 elements
      do j=1,InputFileData%BladeProps(k)%NumBlNds-1
         call MeshConstructElement( u%BladeMotion(k), ELEMENT_LINE2, errStat2, errMsg2, p1=j, p2=j+1 )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      end do !j
            
      call MeshCommit(u%BladeMotion(k), errStat2, errMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName//':BladeMotion'//trim(num2lstr(k)) )
            
      if (errStat >= AbortErrLev) return

      
      u%BladeMotion(k)%Orientation     = u%BladeMotion(k)%RefOrientation
      u%BladeMotion(k)%TranslationDisp = 0.0_R8Ki
      u%BladeMotion(k)%TranslationVel  = 0.0_ReKi
      u%BladeMotion(k)%RotationVel     = 0.0_ReKi
      u%BladeMotion(k)%TranslationAcc  = 0.0_ReKi
         
               
   
   end do !k=numBlades
   
   
   
      !................
      ! Nacelle
      !................
      call MeshCreate ( BlankMesh = u%NacelleMotion &
                       ,IOS       = COMPONENT_INPUT &
                       ,Nnodes    = 1               &
                       ,ErrStat   = ErrStat2        &
                       ,ErrMess   = ErrMsg2         &
                       ,Orientation     = .true.    &
                       ,TranslationDisp = .true.    &
                       ,TranslationVel  = .true.    &
                      )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      if (errStat >= AbortErrLev) return
            
         ! set node initial position/orientation
      position = InitInp%NacellePosition

      call MeshPositionNode(u%NacelleMotion, 1, position, errStat2, errMsg2, orient=InitInp%NacelleOrientation)
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      call MeshConstructElement( u%NacelleMotion, ELEMENT_POINT, errStat2, errMsg2, p1=1 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      call MeshCommit(u%NacelleMotion, errStat2, errMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
            
      if (errStat >= AbortErrLev) return

   
   
end subroutine Init_u
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine sets AeroDyn parameters for use during the simulation; these variables are not changed after AD_Init.
subroutine SetParameters( InitInp, InputFileData, RotData, p, p_AD, ErrStat, ErrMsg )
   TYPE(AD_InitInputType),       intent(in   )  :: InitInp          !< Input data for initialization routine, out is needed because of copy below
   TYPE(AD_InputFile),           INTENT(INout)  :: InputFileData    !< Data stored in the module's input file -- intent(out) only for move_alloc statements
   TYPE(RotInputFile),           INTENT(INout)  :: RotData          !< Data stored in the module's input file -- intent(out) only for move_alloc statements
   TYPE(RotParameterType),       INTENT(INOUT)  :: p                !< Parameters
   TYPE(AD_ParameterType),       INTENT(INOUT)  :: p_AD             !< Parameters
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat          !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg           !< Error message if ErrStat /= ErrID_None


      ! Local variables
   CHARACTER(ErrMsgLen)                          :: ErrMsg2         ! temporary Error message if ErrStat /= ErrID_None
   INTEGER(IntKi)                                :: ErrStat2        ! temporary Error status of the operation
   !INTEGER(IntKi)                                :: i, j
   character(*), parameter                       :: RoutineName = 'SetParameters'
   
      ! Initialize variables for this routine

   ErrStat  = ErrID_None
   ErrMsg   = ""

   p_AD%UA_Flag       = InputFileData%AFAeroMod == AFAeroMod_BL_unsteady
   
   p_AD%DT            = InputFileData%DTAero
   p_AD%WakeMod       = InputFileData%WakeMod
   p%TwrPotent        = InputFileData%TwrPotent
   p%TwrShadow        = InputFileData%TwrShadow
   p%TwrAero          = InputFileData%TwrAero
   p%CavitCheck       = InputFileData%CavitCheck
   

   if (InitInp%Linearize .and. InputFileData%WakeMod == WakeMod_BEMT) then
      p%FrozenWake = InputFileData%FrozenWake
   else
      p%FrozenWake = .FALSE.
   end if

   p%CompAA = InputFileData%CompAA
   
   ! NOTE: In the following we use InputFileData%BladeProps(1)%NumBlNds as the number of aero nodes on EACH blade, 
   !       but if AD changes this, then it must be handled in the Glue-code linearization code, too (and elsewhere?) !
   if (p%NumBlades>0) then
      p%NumBlNds         = RotData%BladeProps(1)%NumBlNds
   else
      p%NumBlNds         = 0
   endif
   if (p%TwrPotent == TwrPotent_none .and. p%TwrShadow == TwrShadow_none .and. .not. p%TwrAero) then
      p%NumTwrNds     = 0
   else
      p%NumTwrNds     = RotData%NumTwrNds
      
      call move_alloc( RotData%TwrDiam, p%TwrDiam )
      call move_alloc( RotData%TwrCd,   p%TwrCd )      
      call move_alloc( RotData%TwrTI,   p%TwrTI )      
   end if
   
   p%Gravity          = InitInp%Gravity
   p%AirDens          = InputFileData%AirDens          
   p%KinVisc          = InputFileData%KinVisc
   p%Patm             = InputFileData%Patm
   p%Pvap             = InputFileData%Pvap
   p%SpdSound         = InputFileData%SpdSound
   p%WtrDpth          = InitInp%WtrDpth
   p%MSL2SWL          = InitInp%MSL2SWL

  !p%AFI     ! set in call to AFI_Init() [called early because it wants to use the same echo file as AD]
  !p%BEMT    ! set in call to BEMT_Init()
      
  !p%RootName       = TRIM(InitInp%RootName)//'.AD'   ! set earlier to it could be used   
   
   p%numOuts          = InputFileData%NumOuts  
   p%NBlOuts          = InputFileData%NBlOuts      
   p%BlOutNd          = InputFileData%BlOutNd
   
   if (p%NumTwrNds > 0) then
      p%NTwOuts = InputFileData%NTwOuts
      p%TwOutNd = InputFileData%TwOutNd
   else
      p%NTwOuts = 0
   end if
   
   call SetOutParam(InputFileData%OutList, p, p_AD, ErrStat2, ErrMsg2 ) ! requires: p%NumOuts, p%numBlades, p%NumBlNds, p%NumTwrNds; sets: p%OutParam.
      call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      if (ErrStat >= AbortErrLev) return  
   



      ! Set the nodal output parameters.  Note there is some validation in this, so we might get an error from here.
   CALL AllBldNdOuts_SetParameters( InputFileData, p, p_AD, ErrStat2, ErrMsg2 )
      call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)



   
end subroutine SetParameters
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine is called at the end of the simulation.
subroutine AD_End( u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg )
!..................................................................................................................................

      TYPE(AD_InputType),           INTENT(INOUT)  :: u           !< System inputs
      TYPE(AD_ParameterType),       INTENT(INOUT)  :: p           !< Parameters
      TYPE(AD_ContinuousStateType), INTENT(INOUT)  :: x           !< Continuous states
      TYPE(AD_DiscreteStateType),   INTENT(INOUT)  :: xd          !< Discrete states
      TYPE(AD_ConstraintStateType), INTENT(INOUT)  :: z           !< Constraint states
      TYPE(AD_OtherStateType),      INTENT(INOUT)  :: OtherState  !< Other states
      TYPE(AD_OutputType),          INTENT(INOUT)  :: y           !< System outputs
      TYPE(AD_MiscVarType),         INTENT(INOUT)  :: m           !< Misc/optimization variables
      INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     !< Error status of the operation
      CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      !< Error message if ErrStat /= ErrID_None
      
      integer                                      :: iW



         ! Initialize ErrStat

      ErrStat = ErrID_None
      ErrMsg  = ""


         ! Place any last minute operations or calculations here:
         ! End the FVW submodule
      if (p%WakeMod == WakeMod_FVW ) then

         if ( p%UA_Flag ) then
            do iW=1,p%FVW%nWings
               call UA_End(m%FVW%W(iW)%p_UA)
            enddo
         end if

         call FVW_End( m%FVW_u, p%FVW, x%FVW, xd%FVW, z%FVW, OtherState%FVW, m%FVW_y, m%FVW, ErrStat, ErrMsg )
      
      endif
      

         ! Close files here:



         ! Destroy the input data:

      CALL AD_DestroyInput( u, ErrStat, ErrMsg )


         ! Destroy the parameter data:

      CALL AD_DestroyParam( p, ErrStat, ErrMsg )


         ! Destroy the state data:

      CALL AD_DestroyContState(   x,           ErrStat, ErrMsg )
      CALL AD_DestroyDiscState(   xd,          ErrStat, ErrMsg )
      CALL AD_DestroyConstrState( z,           ErrStat, ErrMsg )
      CALL AD_DestroyOtherState(  OtherState,  ErrStat, ErrMsg )
      CALL AD_DestroyMisc(        m,           ErrStat, ErrMsg ) 

         ! Destroy the output data:

      CALL AD_DestroyOutput( y, ErrStat, ErrMsg )




END SUBROUTINE AD_End
!----------------------------------------------------------------------------------------------------------------------------------
!> Loose coupling routine for solving for constraint states, integrating continuous states, and updating discrete and other states.
!! Continuous, constraint, discrete, and other states are updated for t + Interval
subroutine AD_UpdateStates( t, n, u, utimes, p, x, xd, z, OtherState, m, errStat, errMsg )
!..................................................................................................................................

   real(DbKi),                     intent(in   ) :: t          !< Current simulation time in seconds
   integer(IntKi),                 intent(in   ) :: n          !< Current simulation time step n = 0,1,...
   type(AD_InputType),             intent(inout) :: u(:)       !< Inputs at utimes (out only for mesh record-keeping in ExtrapInterp routine)
   real(DbKi),                     intent(in   ) :: utimes(:)  !< Times associated with u(:), in seconds
   type(AD_ParameterType),         intent(in   ) :: p          !< Parameters
   type(AD_ContinuousStateType),   intent(inout) :: x          !< Input: Continuous states at t;
                                                               !!   Output: Continuous states at t + Interval
   type(AD_DiscreteStateType),     intent(inout) :: xd         !< Input: Discrete states at t;
                                                               !!   Output: Discrete states at t  + Interval
   type(AD_ConstraintStateType),   intent(inout) :: z          !< Input: Constraint states at t;
                                                               !!   Output: Constraint states at t+dt
   type(AD_OtherStateType),        intent(inout) :: OtherState !< Input: Other states at t;
                                                               !!   Output: Other states at t+dt
   type(AD_MiscVarType),           intent(inout) :: m          !< Misc/optimization variables
   integer(IntKi),                 intent(  out) :: errStat    !< Error status of the operation
   character(*),                   intent(  out) :: errMsg     !< Error message if ErrStat /= ErrID_None

   ! local variables
   integer(intKi)                               :: iR          ! Counter on rotors
   type(AD_InputType)                           :: uInterp     ! Interpolated/Extrapolated input
   integer(intKi)                               :: ErrStat2          ! temporary Error status
   character(ErrMsgLen)                         :: ErrMsg2           ! temporary Error message
   character(*), parameter                      :: RoutineName = 'AD_UpdateStates'
      
   ErrStat = ErrID_None
   ErrMsg  = ""
     

   call AD_CopyInput( u(1), uInterp, MESH_NEWCOPY, errStat2, errMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
      if (ErrStat >= AbortErrLev) then
         call Cleanup()
         return
      end if

      ! set values of m%BEMT_u(2) from inputs interpolated at t+dt:
      ! NOTE: this is different than OpenFAST, which has t+dt at u(1)
   call AD_Input_ExtrapInterp(u,utimes,uInterp,t+p%DT, errStat2, errMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

   do iR = 1,size(p%rotors)
      call SetInputs(p%rotors(iR), p, uInterp%rotors(iR), m%rotors(iR), 2, errStat2, errMsg2)      
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   enddo
      
      ! set values of m%BEMT_u(1) from inputs (uInterp) interpolated at t:
      ! NOTE: this is different than OpenFAST, which has t at u(2)
      ! I'm doing this second in case we want the other misc vars at t as before, but I don't think it matters      
   call AD_Input_ExtrapInterp(u,utimes,uInterp, t, errStat2, errMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

   do iR = 1,size(p%rotors)
      call SetInputs(p%rotors(iR), p, uInterp%rotors(iR), m%rotors(iR), 1, errStat2, errMsg2)      
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   enddo
         

   if (p%WakeMod /= WakeMod_FVW) then
      do iR = 1,size(p%rotors)
            ! Call into the BEMT update states    NOTE:  This is a non-standard framework interface!!!!!  GJH
            ! Also note BEMT_u(1) and BEMT_u(2) are not following the OpenFAST convention for t+dt, t
         call BEMT_UpdateStates(t, n, m%rotors(iR)%BEMT_u(1), m%rotors(iR)%BEMT_u(2),  p%rotors(iR)%BEMT, x%rotors(iR)%BEMT, xd%rotors(iR)%BEMT, z%rotors(iR)%BEMT, OtherState%rotors(iR)%BEMT, p%AFI, m%rotors(iR)%BEMT, errStat2, errMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

            ! Call AeroAcoustics updates states
         if ( p%rotors(iR)%CompAA ) then
            ! We need the outputs from BEMT as inputs to AeroAcoustics module
            ! Also,  SetInputs() [called above] calls SetInputsForBEMT() which in turn establishes current versions of the Global to local transformations we need as inputs to AA
            call SetInputsForAA(p%rotors(iR), u(1)%rotors(iR), m%rotors(iR), errStat2, errMsg2)  
               call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
            call AA_UpdateStates(t,  n, m%rotors(iR)%AA, m%rotors(iR)%AA_u, p%rotors(iR)%AA, xd%rotors(iR)%AA,  errStat2, errMsg2)
               call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         end if       
      enddo

   else  ! Call the FVW sub module
         ! This needs to extract the inputs from the AD data types (mesh) and copy pieces for the FVW module
      call SetInputsForFVW(p, u, m, errStat2, errMsg2)
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         ! Note: the setup is handled above in the SetInputs routine
      call FVW_UpdateStates( t, n, m%FVW_u, utimes, p%FVW, x%FVW, xd%FVW, z%FVW, OtherState%FVW, p%AFI, m%FVW, ErrStat2, ErrMsg2 )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         ! The wind points are passed out as other states.  These really correspond to the propogation of the vortex to the next wind position.
      if (allocated(OtherState%WakeLocationPoints)) then
         OtherState%WakeLocationPoints = m%FVW%r_wind
      endif
      ! UA TODO
      !call UA_UpdateState_Wrapper(p%AFI, n, p%FVW, x%FVW, xd%FVW, OtherState%FVW, m%FVW, ErrStat2, ErrMsg2)
      !   call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   endif
           
   call Cleanup()
   
contains
   subroutine Cleanup()
      call AD_DestroyInput( uInterp, errStat2, errMsg2)
   end subroutine Cleanup
end subroutine AD_UpdateStates
!----------------------------------------------------------------------------------------------------------------------------------
!> Routine for computing outputs, used in both loose and tight coupling.
!! This subroutine is used to compute the output channels (motions and loads) and place them in the WriteOutput() array.
!! The descriptions of the output channels are not given here. Please see the included OutListParameters.xlsx sheet for
!! for a complete description of each output parameter.
subroutine AD_CalcOutput( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, NeedWriteOutput )
! NOTE: no matter how many channels are selected for output, all of the outputs are calculated
! All of the calculated output channels are placed into the m%AllOuts(:), while the channels selected for outputs are
! placed in the y%WriteOutput(:) array.
!..................................................................................................................................

   REAL(DbKi),                   INTENT(IN   )  :: t           !< Current simulation time in seconds
   TYPE(AD_InputType),           INTENT(IN   )  :: u           !< Inputs at Time t
   TYPE(AD_ParameterType),       INTENT(IN   )  :: p           !< Parameters
   TYPE(AD_ContinuousStateType), INTENT(IN   )  :: x           !< Continuous states at t
   TYPE(AD_DiscreteStateType),   INTENT(IN   )  :: xd          !< Discrete states at t
   TYPE(AD_ConstraintStateType), INTENT(IN   )  :: z           !< Constraint states at t
   TYPE(AD_OtherStateType),      INTENT(IN   )  :: OtherState  !< Other states at t
   TYPE(AD_OutputType),          INTENT(INOUT)  :: y           !< Outputs computed at t (Input only so that mesh con-
                                                               !!   nectivity information does not have to be recalculated)
   type(AD_MiscVarType),         intent(inout)  :: m           !< Misc/optimization variables
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      !< Error message if ErrStat /= ErrID_None
   LOGICAL,          OPTIONAL,   INTENT(IN   )  :: NeedWriteOutput     !< Flag to determine if WriteOutput values need to be calculated in this call


      ! NOTE: m%BEMT_u(i) indices are set differently from the way OpenFAST typically sets up the u and uTimes arrays
   integer, parameter                           :: indx = 1  ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer(intKi)                               :: i
   integer(intKi)                               :: iR ! Loop on rotors

   integer(intKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'AD_CalcOutput'
   LOGICAL                                      :: CalcWriteOutput
   
   ErrStat = ErrID_None
   ErrMsg  = ""

   if (present(NeedWriteOutput)) then
      CalcWriteOutput = NeedWriteOutput
   else
      CalcWriteOutput = .true. ! by default, calculate WriteOutput unless told that we do not need it
   end if


   ! SetInputs, Calc BEM Outputs and Twr Outputs 
   do iR=1,size(p%rotors)
      call RotCalcOutput( t, u%rotors(iR), p%rotors(iR), p, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), y%rotors(iR), m%rotors(iR), ErrStat, ErrMsg)
   enddo

   if (p%WakeMod == WakeMod_FVW) then
         ! This needs to extract the inputs from the AD data types (mesh) and copy pieces for the FVW module
      call SetInputsForFVW(p, (/u/), m, errStat2, errMsg2)
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         ! Calculate Outputs at time t
      CALL FVW_CalcOutput( t, m%FVW_u(1), p%FVW, x%FVW, xd%FVW, z%FVW, OtherState%FVW, p%AFI, m%FVW_y, m%FVW, ErrStat2, ErrMsg2 )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

      call SetOutputsFromFVW( t, u, p, OtherState, x, xd, m, y, ErrStat2, ErrMsg2 )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   endif


   !-------------------------------------------------------   
   !     get values to output to file:  
   !-------------------------------------------------------   
   if (CalcWriteOutput) then
      do iR = 1,size(p%rotors)
         if (p%rotors(iR)%NumOuts > 0) then
            call Calc_WriteOutput( p%rotors(iR), p, u%rotors(iR), m%rotors(iR), m, y%rotors(iR), OtherState%rotors(iR), xd%rotors(iR), indx, iR, ErrStat2, ErrMsg2 )   
               call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)      
      
            !...............................................................................................................................   
            ! Place the selected output channels into the WriteOutput(:) array with the proper sign:
            !...............................................................................................................................   

            do i = 1,p%rotors(iR)%NumOuts  ! Loop through all selected output channels
               y%rotors(iR)%WriteOutput(i) = p%rotors(iR)%OutParam(i)%SignM * m%rotors(iR)%AllOuts( p%rotors(iR)%OutParam(i)%Indx )
            end do             ! i - All selected output channels

          end if
       
         y%rotors(iR)%WriteOutput(p%rotors(iR)%NumOuts+1:) = 0.0_ReKi

            ! Now we need to populate the blade node outputs here
         if (p%rotors(iR)%NumBlades > 0) then
            call Calc_WriteAllBldNdOutput( p%rotors(iR), p, u%rotors(iR), m%rotors(iR), m, x%rotors(iR), y%rotors(iR), OtherState%rotors(iR), indx, iR, ErrStat2, ErrMsg2 )   ! Call after normal writeoutput.  Will just postpend data on here.
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         endif
      enddo
   end if
      

end subroutine AD_CalcOutput


subroutine RotCalcOutput( t, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg)
! NOTE: no matter how many channels are selected for output, all of the outputs are calculated
! All of the calculated output channels are placed into the m%AllOuts(:), while the channels selected for outputs are
! placed in the y%WriteOutput(:) array.
!..................................................................................................................................

   REAL(DbKi),                   INTENT(IN   )  :: t           !< Current simulation time in seconds
   TYPE(RotInputType),           INTENT(IN   )  :: u           !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p           !< Parameters
   TYPE(AD_ParameterType),       INTENT(IN   )  :: p_AD        !< Parameters
   TYPE(RotContinuousStateType), INTENT(IN   )  :: x           !< Continuous states at t
   TYPE(RotDiscreteStateType),   INTENT(IN   )  :: xd          !< Discrete states at t
   TYPE(RotConstraintStateType), INTENT(IN   )  :: z           !< Constraint states at t
   TYPE(RotOtherStateType),      INTENT(IN   )  :: OtherState  !< Other states at t
   TYPE(RotOutputType),          INTENT(INOUT)  :: y           !< Outputs computed at t (Input only so that mesh con-
                                                               !!   nectivity information does not have to be recalculated)
   type(RotMiscVarType),         intent(inout)  :: m           !< Misc/optimization variables
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      !< Error message if ErrStat /= ErrID_None

      ! NOTE: m%BEMT_u(i) indices are set differently from the way OpenFAST typically sets up the u and uTimes arrays
   integer, parameter                           :: indx = 1  ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer(intKi)                               :: i
   integer(intKi)                               :: j
   integer(intKi)                               :: iR ! Loop on rotors

   integer(intKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'RotCalcOutput'
   LOGICAL                                      :: CalcWriteOutput
   
   ErrStat = ErrID_None
   ErrMsg  = ""

   call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)      
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

   if (p_AD%WakeMod /= WakeMod_FVW) then
      ! Call the BEMT module CalcOutput.  Notice that the BEMT outputs are purposely attached to AeroDyn's MiscVar structure to
      ! avoid issues with the coupling code

      call BEMT_CalcOutput(t, m%BEMT_u(indx), p%BEMT, x%BEMT, xd%BEMT, z%BEMT, OtherState%BEMT, p_AD%AFI, m%BEMT_y, m%BEMT, ErrStat2, ErrMsg2 )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

      call SetOutputsFromBEMT( p, m, y ) 
        
      if ( p%CompAA ) then
         ! We need the outputs from BEMT as inputs to AeroAcoustics module
         ! Also,  SetInputs() [called above] calls SetInputsForBEMT() which in turn establishes current versions of the Global to local transformations we need as inputs to AA
         call SetInputsForAA(p, u, m, errStat2, errMsg2)  
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         call AA_CalcOutput(t, m%AA_u, p%AA, x%AA, xd%AA,  z%AA, OtherState%AA,  m%AA_y, m%AA, errStat2, errMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
      end if   
   endif 

   if ( p%TwrAero ) then
      call ADTwr_CalcOutput(p, u, m, y, ErrStat2, ErrMsg2 )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)      
   endif

   call AD_CavtCrit(u, p, m, errStat2, errMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)    
   
end subroutine RotCalcOutput


subroutine AD_CavtCrit(u, p, m, errStat, errMsg)
   TYPE(RotInputType),           INTENT(IN   )  :: u           !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p           !< Parameters
   TYPE(RotMiscVarType),         INTENT(INOUT)  :: m           !< Misc/optimization variables
                                                               !!   nectivity information does not have to be recalculated)
   INTEGER(IntKi),               INTENT(  OUT)   :: errStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)   :: errMsg      !< Error message if ErrStat /= ErrID_None
   integer    :: i,j
   real(ReKi) :: SigmaCavitCrit, SigmaCavit

   errStat = ErrID_None
   errMsg  = ''

   if ( p%CavitCheck ) then      ! Calculate the cavitation number for the airfoil at the node in quesiton, and compare to the critical cavitation number based on the vapour pressure and submerged depth       
      do j = 1,p%numBlades ! Loop through all blades
         do i = 1,p%NumBlNds  ! Loop through all nodes
                     
            if ( EqualRealNos( m%BEMT_y%Vrel(i,j), 0.0_ReKi ) ) call SetErrStat( ErrID_Fatal, 'Vrel cannot be zero to do a cavitation check', ErrStat, ErrMsg, 'AD_CavtCrit') 
               if (ErrStat >= AbortErrLev) return
      
            SigmaCavit= -1* m%BEMT_y%Cpmin(i,j) ! Local cavitation number on node j                                               
            SigmaCavitCrit= ( ( p%Patm + ( p%Gravity * (p%WtrDpth - ( u%HubMotion%Position(3,1)+u%HubMotion%TranslationDisp(3,1) ) - (  u%BladeMotion(j)%Position(3,i) + u%BladeMotion(j)%TranslationDisp(3,i) - u%HubMotion%Position(3,1))) * p%airDens)  - p%Pvap ) / ( 0.5_ReKi * p%airDens * m%BEMT_y%Vrel(i,j)**2)) ! Critical value of Sigma, cavitation occurs if local cavitation number is greater than this
                                                                        
               if ( (SigmaCavitCrit < SigmaCavit) .and. (.not. (m%CavitWarnSet(i,j)) ) ) then     
                    call WrScr( NewLine//'Cavitation occurred at blade '//trim(num2lstr(j))//' and node '//trim(num2lstr(i))//'.' )
                    m%CavitWarnSet(i,j) = .true.
               end if 
                           
            m%SigmaCavit(i,j)= SigmaCavit                 
            m%SigmaCavitCrit(i,j)=SigmaCavitCrit  
                           
         end do   ! p%NumBlNds
      end do  ! p%numBlades
   end if   ! Cavitation check
end subroutine AD_CavtCrit

!----------------------------------------------------------------------------------------------------------------------------------
!> Tight coupling routine for solving for the residual of the constraint state equations
subroutine AD_CalcConstrStateResidual( Time, u, p, p_AD, x, xd, z, OtherState, m, z_residual, ErrStat, ErrMsg )
!..................................................................................................................................

   REAL(DbKi),                   INTENT(IN   )   :: Time        !< Current simulation time in seconds
   TYPE(AD_InputType),           INTENT(IN   )   :: u           !< Inputs at Time
   TYPE(AD_ParameterType),       INTENT(IN   )   :: p           !< Parameters
   TYPE(AD_ParameterType),       INTENT(IN   )   :: p_AD        !< Parameters
   TYPE(AD_ContinuousStateType), INTENT(IN   )   :: x           !< Continuous states at Time
   TYPE(AD_DiscreteStateType),   INTENT(IN   )   :: xd          !< Discrete states at Time
   TYPE(AD_ConstraintStateType), INTENT(IN   )   :: z           !< Constraint states at Time (possibly a guess)
   TYPE(AD_OtherStateType),      INTENT(IN   )   :: OtherState  !< Other states at Time
   TYPE(AD_MiscVarType),         INTENT(INOUT)   :: m           !< Misc/optimization variables
   TYPE(AD_ConstraintStateType), INTENT(INOUT)   :: Z_residual  !< Residual of the constraint state equations using
                                                                !!     the input values described above
   INTEGER(IntKi),               INTENT(  OUT)   :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)   :: ErrMsg      !< Error message if ErrStat /= ErrID_None
   

   
      ! Local variables   
   integer(intKi)                                :: iR ! rotor index
   integer(intKi)                                :: ErrStat2
   character(ErrMsgLen)                          :: ErrMsg2
   character(*), parameter                       :: RoutineName = 'AD_CalcConstrStateResidual'
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   

   do iR=1, size(p%rotors)
      call RotCalcConstrStateResidual( Time, u%rotors(iR), p%rotors(iR), p_AD, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), m%rotors(iR), z_residual%rotors(iR), ErrStat, ErrMsg )
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   enddo
   
end subroutine AD_CalcConstrStateResidual

!> Tight coupling routine for solving for the residual of the constraint state equations
subroutine RotCalcConstrStateResidual( Time, u, p, p_AD, x, xd, z, OtherState, m, z_residual, ErrStat, ErrMsg )
!..................................................................................................................................

   REAL(DbKi),                   INTENT(IN   )   :: Time        !< Current simulation time in seconds
   TYPE(RotInputType),           INTENT(IN   )   :: u           !< Inputs at Time
   TYPE(RotParameterType),       INTENT(IN   )   :: p           !< Parameters
   TYPE(AD_ParameterType),       INTENT(IN   )   :: p_AD        !< Parameters
   TYPE(RotContinuousStateType), INTENT(IN   )   :: x           !< Continuous states at Time
   TYPE(RotDiscreteStateType),   INTENT(IN   )   :: xd          !< Discrete states at Time
   TYPE(RotConstraintStateType), INTENT(IN   )   :: z           !< Constraint states at Time (possibly a guess)
   TYPE(RotOtherStateType),      INTENT(IN   )   :: OtherState  !< Other states at Time
   TYPE(RotMiscVarType),         INTENT(INOUT)   :: m           !< Misc/optimization variables
   TYPE(RotConstraintStateType), INTENT(INOUT)   :: z_residual  !< Residual of the constraint state equations using
                                                                !!     the input values described above
   INTEGER(IntKi),               INTENT(  OUT)   :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)   :: ErrMsg      !< Error message if ErrStat /= ErrID_None
   
      ! Local variables   
   integer, parameter                            :: indx = 1  ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer(intKi)                                :: iR ! rotor index
   integer(intKi)                                :: ErrStat2
   character(ErrMsgLen)                          :: ErrMsg2
   character(*), parameter                       :: RoutineName = 'RotCalcConstrStateResidual'
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   if (.not. allocated(z_residual%BEMT%phi)) then ! BEMT_CalcConstrStateResidual expects memory to be allocated, so let's make sure it is
      call AD_CopyRotConstraintStateType( z, z_residual, MESH_NEWCOPY, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   end if
   
   
   call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
                                
      
   call BEMT_CalcConstrStateResidual( Time, m%BEMT_u(indx), p%BEMT, x%BEMT, xd%BEMT, z%BEMT, OtherState%BEMT, m%BEMT, &
                                       z_residual%BEMT, p_AD%AFI, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   
end subroutine RotCalcConstrStateResidual

!----------------------------------------------------------------------------------------------------------------------------------
subroutine RotCalcContStateDeriv( t, u, p, p_AD, x, xd, z, OtherState, m, dxdt, ErrStat, ErrMsg )
! Tight coupling routine for computing derivatives of continuous states
!..................................................................................................................................

   REAL(DbKi),                     INTENT(IN   )  :: t           ! Current simulation time in seconds
   TYPE(RotInputType),             INTENT(IN   )  :: u           ! Inputs at t
   TYPE(RotParameterType),         INTENT(IN   )  :: p           ! Parameters
   TYPE(AD_ParameterType),         INTENT(IN   )  :: p_AD        ! Parameters
   TYPE(RotContinuousStateType),   INTENT(IN   )  :: x           ! Continuous states at t
   TYPE(RotDiscreteStateType),     INTENT(IN   )  :: xd          ! Discrete states at t
   TYPE(RotConstraintStateType),   INTENT(IN   )  :: z           ! Constraint states at t
   TYPE(RotOtherStateType),        INTENT(IN   )  :: OtherState  ! Other states at t
   TYPE(RotMiscVarType),           INTENT(INOUT)  :: m           ! Misc/optimization variables
   TYPE(RotContinuousStateType),   INTENT(INOUT)  :: dxdt        ! Continuous state derivatives at t
   INTEGER(IntKi),                 INTENT(  OUT)  :: ErrStat     ! Error status of the operation
   CHARACTER(*),                   INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

   ! local variables
   INTEGER(IntKi)                                 :: iR          ! temporary Error status of the operation
   CHARACTER(ErrMsgLen)                           :: ErrMsg2     ! temporary Error message if ErrStat /= ErrID_None
   INTEGER(IntKi)                                 :: ErrStat2    ! temporary Error status of the operation
   CHARACTER(*), PARAMETER                        :: RoutineName = 'RotCalcContStateDeriv'
   
   INTEGER(IntKi), parameter                      :: InputIndex = 1

      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ""

   call SetInputs(p, p_AD, u, m, InputIndex, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   
   call BEMT_CalcContStateDeriv( t, m%BEMT_u(InputIndex), p%BEMT, x%BEMT, xd%BEMT, z%BEMT, OtherState%BEMT, m%BEMT, dxdt%BEMT, p_AD%AFI, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   
END SUBROUTINE RotCalcContStateDeriv
!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine converts the AeroDyn inputs into values that can be used for its submodules. It calculates the disturbed inflow
!! on the blade if tower shadow or tower influence are enabled, then uses these values to set m%BEMT_u(indx).
subroutine SetInputs(p, p_AD, u, m, indx, errStat, errMsg)
   type(RotParameterType),       intent(in   )  :: p                      !< AD parameters
   type(AD_ParameterType),       intent(in   )  :: p_AD                   !< AD parameters
   type(RotInputType),           intent(in   )  :: u                      !< AD Inputs at Time
   type(RotMiscVarType),         intent(inout)  :: m                      !< Misc/optimization variables
   integer,                      intent(in   )  :: indx                   !< index into m%BEMT_u(indx) array; 1=t and 2=t+dt (but not checked here)
   integer(IntKi),               intent(  out)  :: ErrStat                !< Error status of the operation
   character(*),                 intent(  out)  :: ErrMsg                 !< Error message if ErrStat /= ErrID_None
                                 
   ! local variables             
   integer(intKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'SetInputs'
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   ! Disturbed inflow on blade (if tower shadow present)
   call SetDisturbedInflow(p, u, m, errStat, errMsg)

   if (p_AD%WakeMod /= WakeMod_FVW) then
         ! This needs to extract the inputs from the AD data types (mesh) and massage them for the BEMT module
      call SetInputsForBEMT(p, u, m, indx, errStat2, errMsg2)
         call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   endif
end subroutine SetInputs

!----------------------------------------------------------------------------------------------------------------------------------
!> Disturbed inflow on the blade if tower shadow or tower influence are enabled
subroutine SetDisturbedInflow(p, u, m, errStat, errMsg)
   type(RotParameterType),       intent(in   )  :: p                      !< AD parameters
   type(RotInputType),           intent(in   )  :: u                      !< AD Inputs at Time
   type(RotMiscVarType),         intent(inout)  :: m                      !< Misc/optimization variables
   integer(IntKi),               intent(  out)  :: errStat                !< Error status of the operation
   character(*),                 intent(  out)  :: errMsg                 !< Error message if ErrStat /= ErrID_None
   ! local variables             
   integer(intKi)                               :: errStat2
   character(ErrMsgLen)                         :: errMsg2
   character(*), parameter                      :: RoutineName = 'SetDisturbedInflow'
   errStat = ErrID_None
   errMsg  = ""
   if (p%TwrPotent /= TwrPotent_none .or. p%TwrShadow /= TwrShadow_none) then
      call TwrInfl( p, u, m, errStat2, errMsg2 ) ! NOTE: tower clearance is computed here..
         call SetErrStat(errStat2, errMsg2, errStat, errMsg, RoutineName)
   else
      m%DisturbedInflow = u%InflowOnBlade
   end if

end subroutine SetDisturbedInflow


!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine sets m%BEMT_u(indx).
subroutine SetInputsForBEMT(p, u, m, indx, errStat, errMsg)

   type(RotParameterType),  intent(in   )  :: p                               !< AD parameters
   type(RotInputType),      intent(in   )  :: u                               !< AD Inputs at Time
   type(RotMiscVarType),    intent(inout)  :: m                               !< Misc/optimization variables
   integer,                 intent(in   )  :: indx                            !< index into m%BEMT_u array; must be 1 or 2 (but not checked here)
   integer(IntKi),          intent(  out)  :: ErrStat                         !< Error status of the operation
   character(*),            intent(  out)  :: ErrMsg                          !< Error message if ErrStat /= ErrID_None
      
   ! local variables
   real(R8Ki)                              :: x_hat(3)
   real(R8Ki)                              :: y_hat(3)
   real(R8Ki)                              :: z_hat(3)
   real(R8Ki)                              :: x_hat_disk(3)
   real(R8Ki)                              :: y_hat_disk(3)
   real(R8Ki)                              :: z_hat_disk(3)
   real(ReKi)                              :: tmp(3)
   real(ReKi)                              :: tmp_sz, tmp_sz_y
   real(ReKi)                              :: rmax
   real(R8Ki)                              :: thetaBladeNds(p%NumBlNds,p%NumBlades)
   real(R8Ki)                              :: Azimuth(p%NumBlades)
   
   integer(intKi)                          :: j                      ! loop counter for nodes
   integer(intKi)                          :: k                      ! loop counter for blades
   integer(intKi)                          :: ErrStat2
   character(ErrMsgLen)                    :: ErrMsg2
   character(*), parameter                 :: RoutineName = 'SetInputsForBEMT'
   
   ! note ErrStat and ErrMsg are set in GeomWithoutSweepPitchTwist:

      ! Get disk average values and orientations
   call DiskAvgValues(p, u, m, x_hat_disk, y_hat_disk, z_hat_disk, Azimuth)
   call GeomWithoutSweepPitchTwist(p,u,m,thetaBladeNds,ErrStat,ErrMsg)
   if (ErrStat >= AbortErrLev) return

      ! Velocity in disk normal
   m%BEMT_u(indx)%Un_disk  = m%V_dot_x
     
      ! "Angular velocity of rotor" rad/s
   m%BEMT_u(indx)%omega   = dot_product( u%HubMotion%RotationVel(:,1), x_hat_disk )
   
      ! "Angle between the vector normal to the rotor plane and the wind vector (e.g., the yaw angle in the case of no tilt)" rad 
   tmp_sz = TwoNorm( m%V_diskAvg )
   if ( EqualRealNos( tmp_sz, 0.0_ReKi ) ) then
      m%BEMT_u(indx)%chi0 = 0.0_ReKi
   else
         ! make sure we don't have numerical issues that make the ratio outside +/-1
      tmp_sz_y = min(  1.0_ReKi, m%V_dot_x / tmp_sz )
      tmp_sz_y = max( -1.0_ReKi, tmp_sz_y )
      
      m%BEMT_u(indx)%chi0 = acos( tmp_sz_y )
      
   end if
   
      ! "Azimuth angle" rad
   m%bemt_u(indx)%psi = Azimuth

      ! theta, "Twist angle (includes all sources of twist)" rad
      ! Vx, "Local axial velocity at node" m/s
      ! Vy, "Local tangential velocity at node" m/s
   do k=1,p%NumBlades
      do j=1,p%NumBlNds         
         
         m%BEMT_u(indx)%theta(j,k) = thetaBladeNds(j,k) ! local pitch + twist (aerodyanmic + elastic) angle of the jth node in the kth blade
                           
         x_hat = m%WithoutSweepPitchTwist(1,:,j,k)
         y_hat = m%WithoutSweepPitchTwist(2,:,j,k)
         tmp   = m%DisturbedInflow(:,j,k) - u%BladeMotion(k)%TranslationVel(:,j) ! rel_V(j)_Blade(k)
         
         m%BEMT_u(indx)%Vx(j,k) = dot_product( tmp, x_hat ) ! normal component (normal to the plane, not chord) of the inflow velocity of the jth node in the kth blade
         m%BEMT_u(indx)%Vy(j,k) = dot_product( tmp, y_hat ) ! tangential component (tangential to the plane, not chord) of the inflow velocity of the jth node in the kth blade

         
         !jmj says omega_z and PitchRate are the same things
         ! inputs for DBEMT (DBEMT_Mod == DBEMT_cont_tauConst)
         if (allocated(m%BEMT_u(indx)%Vx_elast_dot)) then
            m%BEMT_u(indx)%Vx_elast_dot(j,k)  = dot_product( u%BladeMotion(k)%TranslationAcc(:,j), x_hat ) ! normal component (normal to the plane, not chord) of the inflow velocity of the jth node in the kth blade
            m%BEMT_u(indx)%Vy_elast_dot(j,k)  = dot_product( u%BladeMotion(k)%TranslationAcc(:,j), y_hat ) ! tangential component (tangential to the plane, not chord) of the inflow velocity of the jth node in the kth blade
         end if
         ! inputs for CUA (and CDBEMT):
         m%BEMT_u(indx)%omega_z(j,k)       = dot_product( u%BladeMotion(k)%RotationVel(   :,j), m%WithoutSweepPitchTwist(3,:,j,k) ) ! rotation of no-sweep-pitch coordinate system around z of the jth node in the kth blade
         
      end do !j=nodes
   end do !k=blades
   
   
      ! "Radial distance from center-of-rotation to node" m
   
   do k=1,p%NumBlades
      do j=1,p%NumBlNds
         
            ! displaced position of the jth node in the kth blade relative to the hub:
         tmp =  u%BladeMotion(k)%Position(:,j) + u%BladeMotion(k)%TranslationDisp(:,j) &
              - u%HubMotion%Position(:,1)      - u%HubMotion%TranslationDisp(:,1)
         
            ! local radius (normalized distance from rotor centerline)
         tmp_sz_y = dot_product( tmp, y_hat_disk )**2
         tmp_sz   = dot_product( tmp, z_hat_disk )**2
         m%BEMT_u(indx)%rLocal(j,k) = sqrt( tmp_sz + tmp_sz_y )
         
      end do !j=nodes      
   end do !k=blades  
  
   m%BEMT_u(indx)%UserProp = u%UserProp
   
   
   !..........................
   ! TSR
   !..........................
   if ( EqualRealNos( m%V_dot_x, 0.0_ReKi ) ) then
      m%BEMT_u(indx)%TSR = 0.0_ReKi
   else
      rmax = 0.0_ReKi
      do k=1,min(p%NumBlades,MaxBl)
         do j=1,p%NumBlNds
            rmax = max(rmax, m%BEMT_u(indx)%rLocal(j,k) )
         end do !j=nodes
      end do !k=blades
      m%BEMT_u(indx)%TSR = m%BEMT_u(indx)%omega * rmax / m%V_dot_x
   end if
         
end subroutine SetInputsForBEMT
!----------------------------------------------------------------------------------------------------------------------------------
subroutine DiskAvgValues(p, u, m, x_hat_disk, y_hat_disk, z_hat_disk, Azimuth)
   type(RotParameterType),  intent(in   )  :: p                               !< AD parameters
   type(RotInputType),      intent(in   )  :: u                               !< AD Inputs at Time
   type(RotMiscVarType),    intent(inout)  :: m                               !< Misc/optimization variables
   real(R8Ki),              intent(  out)  :: x_hat_disk(3)
   real(R8Ki),              intent(  out)  :: y_hat_disk(3)
   real(R8Ki),              intent(  out)  :: z_hat_disk(3)
   real(R8Ki),              intent(  out)  :: Azimuth(p%NumBlades)
   real(ReKi)                              :: z_hat(3)
   real(ReKi)                              :: tmp(3)
   real(ReKi)                              :: tmp_sz, tmp_sz_y
   integer(intKi)                          :: j                      ! loop counter for nodes
   integer(intKi)                          :: k                      ! loop counter for blades

      ! calculate disk-averaged relative wind speed, V_DiskAvg
   m%V_diskAvg = 0.0_ReKi
   do k=1,p%NumBlades
      do j=1,p%NumBlNds
         tmp = m%DisturbedInflow(:,j,k) - u%BladeMotion(k)%TranslationVel(:,j)
         m%V_diskAvg = m%V_diskAvg + tmp
      end do
   end do
   m%V_diskAvg = m%V_diskAvg / real( p%NumBlades * p%NumBlNds, ReKi )

      ! orientation vectors:
   x_hat_disk = u%HubMotion%Orientation(1,:,1) !actually also x_hat_hub

   m%V_dot_x  = dot_product( m%V_diskAvg, x_hat_disk )
   tmp    = m%V_dot_x * x_hat_disk - m%V_diskAvg
   tmp_sz = TwoNorm(tmp)
   if ( EqualRealNos( tmp_sz, 0.0_ReKi ) ) then
      y_hat_disk = u%HubMotion%Orientation(2,:,1)
      z_hat_disk = u%HubMotion%Orientation(3,:,1)
   else
     y_hat_disk = tmp / tmp_sz
     z_hat_disk = cross_product( m%V_diskAvg, x_hat_disk ) / tmp_sz
  end if

      ! "Azimuth angle" rad
   do k=1,p%NumBlades
      z_hat = u%BladeRootMotion(k)%Orientation(3,:,1)
      tmp_sz_y = -1.0*dot_product(z_hat,y_hat_disk)
      tmp_sz   =      dot_product(z_hat,z_hat_disk)
      if ( EqualRealNos(tmp_sz_y,0.0_ReKi) .and. EqualRealNos(tmp_sz,0.0_ReKi) ) then
         Azimuth(k) = 0.0_ReKi
      else
         Azimuth(k) = atan2( tmp_sz_y, tmp_sz )
      end if
   end do
end subroutine DiskAvgValues
!----------------------------------------------------------------------------------------------------------------------------------
subroutine GeomWithoutSweepPitchTwist(p,u,m,thetaBladeNds,ErrStat,ErrMsg)
   type(RotParameterType),  intent(in   )  :: p                               !< AD parameters
   type(RotInputType),      intent(in   )  :: u                               !< AD Inputs at Time
   type(RotMiscVarType),    intent(inout)  :: m                               !< Misc/optimization variables
   real(R8Ki),              intent(  out)  :: thetaBladeNds(p%NumBlNds,p%NumBlades)
   integer(IntKi),          intent(  out)  :: ErrStat                         !< Error status of the operation
   character(*),            intent(  out)  :: ErrMsg                          !< Error message if ErrStat /= ErrID_None
   real(R8Ki)                              :: theta(3)
   real(R8Ki)                              :: orientation(3,3)
   real(R8Ki)                              :: orientation_nopitch(3,3)

   integer(intKi)                          :: j                      ! loop counter for nodes
   integer(intKi)                          :: k                      ! loop counter for blades
   integer(intKi)                          :: ErrStat2
   character(ErrMsgLen)                    :: ErrMsg2
   character(*), parameter                 :: RoutineName = 'GeomWithoutSweepPitchTwist'

   ErrStat = ErrID_None
   ErrMsg  = ""

   if (p%AeroProjMod==0) then
         ! theta, "Twist angle (includes all sources of twist)" rad
         ! Vx, "Local axial velocity at node" m/s
         ! Vy, "Local tangential velocity at node" m/s
      do k=1,p%NumBlades
            ! construct system equivalent to u%BladeRootMotion(k)%Orientation, but without the blade-pitch angle:
         ! orientation = rotation from hub 2 bl
         call LAPACK_gemm( 'n', 't', 1.0_R8Ki, u%BladeRootMotion(k)%Orientation(:,:,1), u%HubMotion%Orientation(:,:,1), 0.0_R8Ki, orientation, errStat2, errMsg2)
            call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
         theta = EulerExtract( orientation ) !hub_theta_root(k)
         if (k<=3) then
            m%AllOuts( BPitch(  k) ) = -theta(3)*R2D ! save this value of pitch for potential output
         endif
         theta(3) = 0.0_ReKi
         m%hub_theta_x_root(k) = theta(1)   ! save this value for FAST.Farm

         orientation = EulerConstruct( theta ) ! rotation from hub 2 non-pitched blade
         orientation_nopitch = matmul( orientation, u%HubMotion%Orientation(:,:,1) ) ! withoutPitch_theta_Root(k) ! rotation from global 2 non-pitched blade

         do j=1,p%NumBlNds

               ! form coordinate system equivalent to u%BladeMotion(k)%Orientation(:,:,j) but without live sweep (due to in-plane
               ! deflection), blade-pitch and twist (aerodynamic + elastic) angles:

            ! orientation = matmul( u%BladeMotion(k)%Orientation(:,:,j), transpose(orientation_nopitch) )
            ! orientation = rotation from non pitched blade 2 balde section
            call LAPACK_gemm( 'n', 't', 1.0_R8Ki, u%BladeMotion(k)%Orientation(:,:,j), orientation_nopitch, 0.0_R8Ki, orientation, errStat2, errMsg2)
               call SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
            theta = EulerExtract( orientation ) !root(k)WithoutPitch_theta(j)_blade(k)

            thetaBladeNds(j,k) = -theta(3) ! local pitch + twist (aerodyanmic + elastic) angle of the jth node in the kth blade


            theta(1) = 0.0_ReKi
            theta(3) = 0.0_ReKi
            m%Curve(j,k) = theta(2)  ! save value for possible output later
            m%WithoutSweepPitchTwist(:,:,j,k) = matmul( EulerConstruct( theta ), orientation_nopitch ) ! WithoutSweepPitch+Twist_theta(j)_Blade(k)

         end do !j=nodes
      end do !k=blades
   else if (p%AeroProjMod==1) then
      ! Generic blade, we don't assume where the axes are, and we keep the default orientation
      do k=1,p%NumBlades
         m%hub_theta_x_root(k) = 0.0_ReKi ! ill-defined, TODO
         do j=1,p%NumBlNds
            thetaBladeNds(j,k) = 0.0_ReKi ! local pitch + twist (aerodyanmic + elastic) angle of the jth node in the kth blade
            m%Curve(j,k) = 0.0_ReKi ! ill-defined, TODO
            m%WithoutSweepPitchTwist(:,:,j,k) = u%BladeMotion(k)%Orientation(:,:,j)
         enddo
      enddo
   else
      ErrStat = ErrID_Fatal
      ErrMsg ='GeomWithoutSweepPitchTwist: AeroProjMod not supported '//trim(num2lstr(p%AeroProjMod))
   endif
end subroutine GeomWithoutSweepPitchTwist
!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine sets m%FVW_u(indx).
subroutine SetInputsForFVW(p, u, m, errStat, errMsg)

   type(AD_ParameterType),  intent(in   )  :: p                               !< AD parameters
   type(AD_InputType),      intent(in   )  :: u(:)                            !< AD Inputs at Time
   type(AD_MiscVarType),    intent(inout)  :: m                               !< Misc/optimization variables
   integer(IntKi),          intent(  out)  :: ErrStat                         !< Error status of the operation
   character(*),            intent(  out)  :: ErrMsg                          !< Error message if ErrStat /= ErrID_None

   real(R8Ki)                              :: x_hat_disk(3)
   real(R8Ki)                              :: y_hat_disk(3)
   real(R8Ki)                              :: z_hat_disk(3)
   real(R8Ki), allocatable                 :: thetaBladeNds(:,:)
   real(R8Ki), allocatable                 :: Azimuth(:)
   
   integer(intKi)                          :: tIndx
   integer(intKi)                          :: iR ! Loop on rotors
   integer(intKi)                          :: j, k  ! loop counter for blades
   character(*), parameter                 :: RoutineName = 'SetInputsForFVW'
   integer :: iW
   integer :: nWings

   do tIndx=1,size(u)
      do iR =1, size(p%rotors)
         allocate(thetaBladeNds(p%rotors(iR)%NumBlNds, p%rotors(iR)%NumBlades))
         allocate(azimuth(p%rotors(iR)%NumBlades))
         ! Get disk average values and orientations
         ! NOTE: needed because it sets m%V_diskAvg and m%V_dot_x, needed by CalcOutput..
         call DiskAvgValues(p%rotors(iR), u(tIndx)%rotors(iR), m%rotors(iR), x_hat_disk, y_hat_disk, z_hat_disk, Azimuth) 
         call GeomWithoutSweepPitchTwist(p%rotors(iR),u(tIndx)%rotors(iR), m%rotors(iR), thetaBladeNds,ErrStat,ErrMsg)
         if (ErrStat >= AbortErrLev) return

            ! Rather than use a meshcopy, we will just copy what we need to the WingsMesh
            ! NOTE:  MeshCopy requires the source mesh to be INOUT intent
            ! NOTE2: If we change the WingsMesh to not be identical to the BladeMotion mesh, add the mapping stuff here.
         do k=1,p%rotors(iR)%NumBlades
            iW=p%FVW%Bld2Wings(iR,k)

            if ( u(tIndx)%rotors(iR)%BladeMotion(k)%nNodes /= m%FVW_u(tIndx)%WingsMesh(iW)%nNodes ) then
               ErrStat = ErrID_Fatal
               ErrMsg  = RoutineName//": WingsMesh contains different number of nodes than the BladeMotion mesh"
               return
            endif
            m%FVW%W(iW)%PitchAndTwist(:) = thetaBladeNds(:,k) ! local pitch + twist (aerodyanmic + elastic) angle of the jth node in the kth blade
            m%FVW_u(tIndx)%WingsMesh(iW)%TranslationDisp   = u(tIndx)%rotors(iR)%BladeMotion(k)%TranslationDisp
            m%FVW_u(tIndx)%WingsMesh(iW)%Orientation       = u(tIndx)%rotors(iR)%BladeMotion(k)%Orientation
            m%FVW_u(tIndx)%WingsMesh(iW)%TranslationVel    = u(tIndx)%rotors(iR)%BladeMotion(k)%TranslationVel
            m%FVW_u(tIndx)%rotors(iR)%HubPosition    = u(tIndx)%rotors(iR)%HubMotion%Position(:,1) + u(tIndx)%rotors(iR)%HubMotion%TranslationDisp(:,1)
            m%FVW_u(tIndx)%rotors(iR)%HubOrientation = u(tIndx)%rotors(iR)%HubMotion%Orientation(:,:,1)

            ! Inputs for dynamic stall (see SetInputsForBEMT)
            do j=1,p%rotors(iR)%NumBlNds         
               ! inputs for CUA, section pitch/torsion rate
               m%FVW_u(tIndx)%W(iW)%omega_z(j) = dot_product( u(tIndx)%rotors(iR)%BladeMotion(k)%RotationVel(   :,j), m%rotors(iR)%WithoutSweepPitchTwist(3,:,j,k) ) ! rotation of no-sweep-pitch coordinate system around z of the jth node in the kth blade
            end do !j=nodes
         enddo ! k blades
         if (allocated(thetaBladeNds)) deallocate(thetaBladeNds)
         if (allocated(azimuth))       deallocate(azimuth)
      enddo ! iR, rotors

      if (ALLOCATED(m%FVW_u(tIndx)%V_wind)) then
         m%FVW_u(tIndx)%V_wind   = u(tIndx)%InflowWakeVel
         ! Applying tower shadow to V_wind based on r_wind positions
         ! NOTE: m%DisturbedInflow also contains tower shadow and we need it for CalcOutput
         if (p%FVW%TwrShadowOnWake) then
            do iR =1, size(p%rotors)
               if (p%rotors(iR)%TwrPotent /= TwrPotent_none .or. p%rotors(iR)%TwrShadow /= TwrShadow_none) then
                  call TwrInflArray( p%rotors(iR), u(tIndx)%rotors(iR), m%rotors(iR), m%FVW%r_wind, m%FVW_u(tIndx)%V_wind, ErrStat, ErrMsg )
                  if (ErrStat >= AbortErrLev) return
               endif
            enddo
         end if
      endif
      do iR =1, size(p%rotors)
         ! Disturbed inflow for UA on Lifting line Mesh Points
         call SetDisturbedInflow(p%rotors(iR), u(tIndx)%rotors(iR), m%rotors(iR), errStat, errMsg)
         do k=1,p%rotors(iR)%NumBlades
            iW=p%FVW%Bld2Wings(iR,k)
            m%FVW_u(tIndx)%W(iW)%Vwnd_LL(1:3,:) = m%rotors(iR)%DisturbedInflow(1:3,:,k)
         enddo
      enddo
   enddo

end subroutine SetInputsForFVW
!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine sets m%AA_u.
subroutine SetInputsForAA(p, u, m, errStat, errMsg)
   type(RotParameterType),  intent(in   ) :: p        !< AD parameters
   type(RotInputType),      intent(in   ) :: u        !< AD Inputs at Time
   type(RotMiscVarType),    intent(inout) :: m        !< Misc/optimization variables
   integer(IntKi),          intent(  out) :: ErrStat  !< Error status of the operation
   character(*),            intent(  out) :: ErrMsg   !< Error message if ErrStat /= ErrID_None
   ! local variables
   integer(intKi)                         :: i        ! loop counter for nodes
   integer(intKi)                         :: j        ! loop counter for blades
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   do j=1,p%NumBlades
      do i = 1,p%NumBlNds
         ! Get local orientation matrix to transform from blade element coordinates to global coordinates
         m%AA_u%RotGtoL(:,:,i,j) = u%BladeMotion(j)%Orientation(:,:,i)

         ! Get blade element aerodynamic center in global coordinates
         m%AA_u%AeroCent_G(:,i,j) = u%BladeMotion(j)%Position(:,i) + u%BladeMotion(j)%TranslationDisp(:,i)

         ! Set the blade element relative velocity (including induction)
         m%AA_u%Vrel(i,j) = m%BEMT_y%Vrel(i,j)
   
         ! Set the blade element angle of attack
         m%AA_u%AoANoise(i,j) = m%BEMT_y%AOA(i,j)

         ! Set the blade element undisturbed flow
         m%AA_u%Inflow(1,i,j) = u%InflowonBlade(1,i,j)
         m%AA_u%Inflow(2,i,j) = u%InflowonBlade(2,i,j)
         m%AA_u%Inflow(3,i,j) = u%InflowonBlade(3,i,j)
      end do
   end do
end subroutine SetInputsForAA
!----------------------------------------------------------------------------------------------------------------------------------

!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine converts outputs from BEMT (stored in m%BEMT_y) into values on the AeroDyn BladeLoad output mesh.
subroutine SetOutputsFromBEMT(p, m, y )

   type(RotParameterType),  intent(in   )  :: p                               !< AD parameters
   type(RotOutputType),     intent(inout)  :: y                               !< AD outputs 
   type(RotMiscVarType),    intent(inout)  :: m                               !< Misc/optimization variables
   !type(BEMT_OutputType),   intent(in   )  :: BEMT_y                          ! BEMT outputs
   !real(ReKi),              intent(in   )  :: WithoutSweepPitchTwist(:,:,:,:) ! modified orientation matrix

   integer(intKi)                          :: j                      ! loop counter for nodes
   integer(intKi)                          :: k                      ! loop counter for blades
   real(reki)                              :: force(3)
   real(reki)                              :: moment(3)
   real(reki)                              :: q
   
  
   
   force(3)    =  0.0_ReKi          
   moment(1:2) =  0.0_ReKi          
   do k=1,p%NumBlades
      do j=1,p%NumBlNds
                      
         q = 0.5 * p%airDens * m%BEMT_y%Vrel(j,k)**2              ! dynamic pressure of the jth node in the kth blade
         force(1) =  m%BEMT_y%cx(j,k) * q * p%BEMT%chord(j,k)     ! X = normal force per unit length (normal to the plane, not chord) of the jth node in the kth blade
         force(2) = -m%BEMT_y%cy(j,k) * q * p%BEMT%chord(j,k)     ! Y = tangential force per unit length (tangential to the plane, not chord) of the jth node in the kth blade
         moment(3)=  m%BEMT_y%cm(j,k) * q * p%BEMT%chord(j,k)**2  ! M = pitching moment per unit length of the jth node in the kth blade
         
            ! save these values for possible output later:
         m%X(j,k) = force(1)
         m%Y(j,k) = force(2)
         m%M(j,k) = moment(3)
         
            ! note: because force and moment are 1-d arrays, I'm calculating the transpose of the force and moment outputs
            !       so that I don't have to take the transpose of WithoutSweepPitchTwist(:,:,j,k)
         y%BladeLoad(k)%Force(:,j)  = matmul( force,  m%WithoutSweepPitchTwist(:,:,j,k) )  ! force per unit length of the jth node in the kth blade
         y%BladeLoad(k)%Moment(:,j) = matmul( moment, m%WithoutSweepPitchTwist(:,:,j,k) )  ! moment per unit length of the jth node in the kth blade
         
      end do !j=nodes
   end do !k=blades
   
   
end subroutine SetOutputsFromBEMT


!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine converts outputs from FVW (stored in m%FVW_y) into values on the AeroDyn BladeLoad output mesh.
subroutine SetOutputsFromFVW(t, u, p, OtherState, x, xd, m, y, ErrStat, ErrMsg)
   REAL(DbKi),                intent(in   ) :: t
   TYPE(AD_InputType),        intent(in   ) :: u           !< Inputs at Time t
   type(AD_ParameterType),    intent(in   ) :: p           !< AD parameters
   type(AD_OtherStateType),   intent(in   ) :: OtherState  !< OtherState
   type(AD_ContinuousStateType),intent(in ) :: x           !< continuous states
   type(AD_DiscreteStateType),intent(in   ) :: xd          !< Discrete states
   type(AD_OutputType),       intent(inout) :: y           !< AD outputs
   type(AD_MiscVarType),target,intent(inout) :: m           !< Misc/optimization variables
   integer(IntKi),            intent(  out) :: ErrStat     !< Error status of the operation
   character(*),              intent(  out) :: ErrMsg      !< Error message if ErrStat /= ErrID_None

   integer(intKi)                         :: j           ! loop counter for nodes
   integer(intKi)                         :: k           ! loop counter for blades
   real(reki)                             :: force(3)
   real(reki)                             :: moment(3)
   real(reki)                             :: q
   REAL(ReKi)                             :: cp, sp      ! cosine, sine of phi

   ! Local vars for readability
   real(ReKi)                             :: Vind(3)
   real(ReKi)                             :: Vstr(3)
   real(ReKi)                             :: Vwnd(3)
   real(ReKi)                             :: theta
   ! Local variables that we store in misc for nodal outputs
   real(ReKi)                             :: AxInd, TanInd, Vrel, phi, alpha, Re
   type(AFI_OutputType)                   :: AFI_interp             ! Resulting values from lookup table
   real(ReKi)                             :: UrelWind_s(3)          ! Relative wind (wind+str) in section coords
   real(ReKi)                             :: Cx, Cy
   real(ReKi)                             :: Cl_Static, Cd_Static, Cm_Static
   real(ReKi)                             :: Cl_dyn, Cd_dyn, Cm_dyn
   type(UA_InputType), pointer            :: u_UA ! Alias to shorten notations
   integer(IntKi), parameter              :: InputIndex=1      ! we will always use values at t in this routine
   integer(intKi)                         :: iR, iW
   integer(intKi)                         :: ErrStat2
   character(ErrMsgLen)                   :: ErrMsg2

   ErrStat = 0
   ErrMsg = ""

   ! zero forces
   force(3)    =  0.0_ReKi
   moment(1:2) =  0.0_ReKi

   do iR=1,size(p%rotors)
      do k=1,p%rotors(iR)%numBlades
         iW=p%FVW%Bld2Wings(iR,k)
         do j=1,p%rotors(iR)%NumBlNds
            ! --- Computing main aero variables from induction - setting local variables
            Vind = m%FVW_y%W(iW)%Vind(1:3,j)
            Vstr = u%rotors(iR)%BladeMotion(k)%TranslationVel(1:3,j)
            Vwnd = m%rotors(iR)%DisturbedInflow(1:3,j,k)   ! NOTE: contains tower shadow
            theta = m%FVW%W(iW)%PitchAndTwist(j) ! TODO
            call FVW_AeroOuts( m%rotors(iR)%WithoutSweepPitchTwist(1:3,1:3,j,k), u%rotors(iR)%BladeMotion(k)%Orientation(1:3,1:3,j), & ! inputs
                        theta, Vstr(1:3), Vind(1:3), VWnd(1:3), p%rotors(iR)%KinVisc, p%FVW%W(iW)%chord_LL(j), &               ! inputs
                        AxInd, TanInd, Vrel, phi, alpha, Re, UrelWind_s(1:3), ErrStat2, ErrMsg2 )        ! outputs
               call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SetOutputsFromFVW')

            ! Compute steady Airfoil Coefs no matter what..
            call AFI_ComputeAirfoilCoefs( alpha, Re, 0.0_ReKi,  p%AFI(p%FVW%W(iW)%AFindx(j,1)), AFI_interp, ErrStat, ErrMsg )
            Cl_Static = AFI_interp%Cl
            Cd_Static = AFI_interp%Cd
            Cm_Static = AFI_interp%Cm

            ! Set dynamic to the (will be same as static if UA_Flag is false)
            Cl_dyn    = AFI_interp%Cl
            Cd_dyn    = AFI_interp%Cd
            Cm_dyn    = AFI_interp%Cm
            
            if (p%UA_Flag) then
               u_UA => m%FVW%W(iW)%u_UA(j,InputIndex) ! Alias
               ! ....... compute inputs to UA ...........
               u_UA%alpha    = alpha
               u_UA%U        = Vrel
               u_UA%Re       = Re
               ! calculated in m%FVW%u_UA??? :u_UA%UserProp = 0.0_ReKi ! FIX ME

               u_UA%v_ac(1)  = sin(u_UA%alpha)*u_UA%U
               u_UA%v_ac(2)  = cos(u_UA%alpha)*u_UA%U
               ! calculated in m%FVW%u_UA??? : u_UA%omega = dot_product( u%rotors(iR)%BladeMotion(k)%RotationVel(   :,j), m%rotors(iR)%WithoutSweepPitchTwist(3,:,j,k) ) ! rotation of no-sweep-pitch coordinate system around z of the jth node in the kth blade
               call UA_CalcOutput(j, 1, t, u_UA, m%FVW%W(iW)%p_UA, x%FVW%UA(iW), xd%FVW%UA(iW), OtherState%FVW%UA(iW), p%AFI(p%FVW%W(iW)%AFindx(j,1)), m%FVW%W(iW)%y_UA, m%FVW%W(iW)%m_UA, errStat2, errMsg2 )
                  call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SetOutputsFromFVW')
               Cl_dyn = m%FVW%W(iW)%y_UA%Cl
               Cd_dyn = m%FVW%W(iW)%y_UA%Cd
               Cm_dyn = m%FVW%W(iW)%y_UA%Cm
            end if
            cp = cos(phi)
            sp = sin(phi)
            Cx = Cl_dyn*cp + Cd_dyn*sp
            Cy = Cl_dyn*sp - Cd_dyn*cp

            q = 0.5 * p%rotors(iR)%airDens * Vrel**2                ! dynamic pressure of the jth node in the kth blade
            force(1) =  Cx * q * p%FVW%W(iW)%chord_LL(j)        ! X = normal force per unit length (normal to the plane, not chord) of the jth node in the kth blade
            force(2) = -Cy * q * p%FVW%W(iW)%chord_LL(j)        ! Y = tangential force per unit length (tangential to the plane, not chord) of the jth node in the kth blade
            moment(3)=  Cm_dyn * q * p%FVW%W(iW)%chord_LL(j)**2 ! M = pitching moment per unit length of the jth node in the kth blade

               ! save these values for possible output later:
            m%rotors(iR)%X(j,k) = force(1)
            m%rotors(iR)%Y(j,k) = force(2)
            m%rotors(iR)%M(j,k) = moment(3)

               ! note: because force and moment are 1-d arrays, I'm calculating the transpose of the force and moment outputs
               !       so that I don't have to take the transpose of WithoutSweepPitchTwist(:,:,j,k)
            y%rotors(iR)%BladeLoad(k)%Force(:,j)  = matmul( force,  m%rotors(iR)%WithoutSweepPitchTwist(:,:,j,k) )  ! force per unit length of the jth node in the kth blade
            y%rotors(iR)%BladeLoad(k)%Moment(:,j) = matmul( moment, m%rotors(iR)%WithoutSweepPitchTwist(:,:,j,k) )  ! moment per unit length of the jth node in the kth blade

            ! Save results for outputs so we don't have to recalculate them all when we write outputs
            m%FVW%W(iW)%BN_AxInd(j)           = AxInd
            m%FVW%W(iW)%BN_TanInd(j)          = TanInd
            m%FVW%W(iW)%BN_Vrel(j)            = Vrel
            m%FVW%W(iW)%BN_alpha(j)           = alpha
            m%FVW%W(iW)%BN_phi(j)             = phi
            m%FVW%W(iW)%BN_Re(j)              = Re
            m%FVW%W(iW)%BN_UrelWind_s(1:3,j)  = UrelWind_s(1:3)
            m%FVW%W(iW)%BN_Cl_Static(j)       = Cl_Static
            m%FVW%W(iW)%BN_Cd_Static(j)       = Cd_Static
            m%FVW%W(iW)%BN_Cm_Static(j)       = Cm_Static
            m%FVW%W(iW)%BN_Cl(j)              = Cl_dyn
            m%FVW%W(iW)%BN_Cd(j)              = Cd_dyn
            m%FVW%W(iW)%BN_Cm(j)              = Cm_dyn
            m%FVW%W(iW)%BN_Cx(j)              = Cx
            m%FVW%W(iW)%BN_Cy(j)              = Cy
         end do !j=nodes
      end do !k=blades
   end do ! iR rotors

   if ( p%UA_Flag ) then
      ! if ( mod(REAL(t,ReKi),.1) < p%dt) then
      do iW=1,p%FVW%nWings
         call UA_WriteOutputToFile(t, m%FVW%W(iW)%p_UA, m%FVW%W(iW)%y_UA)
      enddo
   end if
   
end subroutine SetOutputsFromFVW
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine validates the inputs from the AeroDyn input files.
SUBROUTINE ValidateNumBlades( NumBl, ErrStat, ErrMsg )
   integer(IntKi),           intent(in)     :: NumBl                             !< Number of blades
   integer(IntKi),           intent(out)    :: ErrStat                           !< Error status
   character(*),             intent(out)    :: ErrMsg                            !< Error message
   ErrStat  = ErrID_None
   ErrMsg   = ''
!    if (NumBl > MaxBl .or. NumBl < 1) call SetErrStat( ErrID_Fatal, 'Number of blades must be between 1 and '//trim(num2lstr(MaxBl))//'.', ErrStat, ErrMsg, 'ValidateNumBlades' )
END SUBROUTINE ValidateNumBlades
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine validates the inputs from the AeroDyn input files.
SUBROUTINE ValidateInputData( InitInp, InputFileData, NumBl, ErrStat, ErrMsg )
!..................................................................................................................................
      
      ! Passed variables:

   type(AD_InitInputType),   intent(in   )  :: InitInp                           !< Input data for initialization routine
   type(AD_InputFile),       intent(in)     :: InputFileData                     !< All the data in the AeroDyn input file
   integer(IntKi),           intent(in)     :: NumBl(:)                          !< Number of blades
   integer(IntKi),           intent(out)    :: ErrStat                           !< Error status
   character(*),             intent(out)    :: ErrMsg                            !< Error message

   
      ! local variables
   integer(IntKi)                           :: k                                 ! Blade number
   integer(IntKi)                           :: j                                 ! node number
   integer(IntKi)                           :: iR                                ! rotor index
   character(*), parameter                  :: RoutineName = 'ValidateInputData'
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   
   if (InputFileData%DTAero <= 0.0)  call SetErrStat ( ErrID_Fatal, 'DTAero must be greater than zero.', ErrStat, ErrMsg, RoutineName )
   if (InputFileData%WakeMod /= WakeMod_None .and. InputFileData%WakeMod /= WakeMod_BEMT .and. InputFileData%WakeMod /= WakeMod_DBEMT .and. InputFileData%WakeMod /= WakeMod_FVW) then
      call SetErrStat ( ErrID_Fatal, 'WakeMod must be '//trim(num2lstr(WakeMod_None))//' (none), '//trim(num2lstr(WakeMod_BEMT))//' (BEMT), '// &
         trim(num2lstr(WakeMod_DBEMT))//' (DBEMT), or '//trim(num2lstr(WakeMod_FVW))//' (FVW).',ErrStat, ErrMsg, RoutineName ) 
   end if
   
   if (InputFileData%AFAeroMod /= AFAeroMod_Steady .and. InputFileData%AFAeroMod /= AFAeroMod_BL_unsteady) then
      call SetErrStat ( ErrID_Fatal, 'AFAeroMod must be '//trim(num2lstr(AFAeroMod_Steady))//' (steady) or '//&
                        trim(num2lstr(AFAeroMod_BL_unsteady))//' (Beddoes-Leishman unsteady).', ErrStat, ErrMsg, RoutineName ) 
   end if
   if (InputFileData%TwrPotent /= TwrPotent_none .and. InputFileData%TwrPotent /= TwrPotent_baseline .and. InputFileData%TwrPotent /= TwrPotent_Bak) then
      call SetErrStat ( ErrID_Fatal, 'TwrPotent must be 0 (none), 1 (baseline potential flow), or 2 (potential flow with Bak correction).', ErrStat, ErrMsg, RoutineName ) 
   end if   
   if (InputFileData%TwrShadow /= TwrShadow_none .and. InputFileData%TwrShadow /= TwrShadow_Powles .and. InputFileData%TwrShadow /= TwrShadow_Eames) then
      call SetErrStat ( ErrID_Fatal, 'TwrShadow must be 0 (none), 1 (Powles tower shadow modle), or 2 (Eames tower shadow model).', ErrStat, ErrMsg, RoutineName ) 
   end if

      ! The following limits are recommended by Juliet Simpson (University of Virginia)
      !  E-mail recommendation:
      !     To test the limits of the model, I've been running steady simulations
      !     with a range of TI inputs. It looks like the model starts to break down
      !     (or at least break the trend of higher TI's) when the TI drops below
      !     0.05. On the other end, the model seems to work up to TI~1 without
      !     breaking down (I checked up to TI=0.99). However, the results aren't
      !     very physically realistic after ~0.35 because it approaches a constant
      !     velocity deficit across the rotor plane, rather than returning to zero
      !     deficit a short distance laterally from the tower. I'm not sure what
      !     the goal of the limits would be, so it's hard for me to say what the
      !     upper cut off should be. If you want it to be physical, perhaps a low
      !     cut off (around 0.4?). If you want it to just not break, and let people
      !     interpret for themselves if it's physical for their scenario, then it
      !     could go to TI~1. I'd recommend imposing limits of 0.05<TI<1, personally.
   if (InputFileData%TwrShadow == TwrShadow_Eames) then
      do iR=1,size(NumBl)
         if ( minval(InputFileData%rotors(iR)%TwrTI) <= 0.05 .or. maxval(InputFileData%rotors(iR)%TwrTI) >= 1.0) call SetErrStat ( ErrID_Fatal, 'The turbulence intensity for the Eames tower shadow model must be greater than 0.05 and less than 1.', ErrStat, ErrMsg, RoutineName )
         if ( maxval(InputFileData%rotors(iR)%TwrTI) >  0.4 .and. maxval(InputFileData%rotors(iR)%TwrTI) <  1.0) call SetErrStat ( ErrID_Warn,  'The turbulence intensity for the Eames tower shadow model above 0.4 may return unphysical results.  Interpret with caution.', ErrStat, ErrMsg, RoutineName )
      enddo
   endif
   
   !if (InitInp%MHK == 0 .and. InputFileData%CavitCheck) call SetErrStat ( ErrID_Fatal, 'A cavitation check can only be performed for an MHK turbine.', ErrStat, ErrMsg, RoutineName ) ! hkr (5/5/21) Uncomment after buoyancy and added mass are implemented
   if (InitInp%MHK == 1 .and. InputFileData%CompAA .or. InitInp%MHK == 2 .and. InputFileData%CompAA) call SetErrStat ( ErrID_Fatal, 'The aeroacoustics module cannot be used with an MHK turbine.', ErrStat, ErrMsg, RoutineName )

   if (InputFileData%AirDens <= 0.0) call SetErrStat ( ErrID_Fatal, 'The density of the working fluid must be greater than zero.', ErrStat, ErrMsg, RoutineName )
   if (InputFileData%KinVisc <= 0.0) call SetErrStat ( ErrID_Fatal, 'The kinesmatic viscosity (KinVisc) must be greater than zero.', ErrStat, ErrMsg, RoutineName )
   if (InputFileData%SpdSound <= 0.0) call SetErrStat ( ErrID_Fatal, 'The speed of sound (SpdSound) must be greater than zero.', ErrStat, ErrMsg, RoutineName )
   if (InputFileData%CavitCheck .and. InputFileData%Pvap <= 0.0) call SetErrStat ( ErrID_Fatal, 'The vapour pressure (Pvap) must be greater than zero.', ErrStat, ErrMsg, RoutineName )
   if (InputFileData%CavitCheck .and. InputFileData%Patm <= 0.0) call SetErrStat ( ErrID_Fatal, 'The atmospheric pressure (Patm)  must be greater than zero.', ErrStat, ErrMsg, RoutineName )

      
   
      ! BEMT/DBEMT inputs
      ! bjj: these checks should probably go into BEMT where they are used...
   if (InputFileData%WakeMod /= WakeMod_none .and. InputFileData%WakeMod /= WakeMod_FVW) then
      if ( InputFileData%MaxIter < 1 ) call SetErrStat( ErrID_Fatal, 'MaxIter must be greater than 0.', ErrStat, ErrMsg, RoutineName )
      
      if ( InputFileData%IndToler < 0.0 .or. EqualRealNos(InputFileData%IndToler, 0.0_ReKi) ) &
         call SetErrStat( ErrID_Fatal, 'IndToler must be greater than 0.', ErrStat, ErrMsg, RoutineName )
   
      if ( InputFileData%SkewMod /= SkewMod_Uncoupled .and. InputFileData%SkewMod /= SkewMod_PittPeters) &  !  .and. InputFileData%SkewMod /= SkewMod_Coupled )
           call SetErrStat( ErrID_Fatal, 'SkewMod must be 1, or 2.  Option 3 will be implemented in a future version.', ErrStat, ErrMsg, RoutineName )      
      
   end if !BEMT/DBEMT checks
   
   
   if ( InputFileData%CavitCheck .and. InputFileData%AFAeroMod == AFAeroMod_BL_unsteady) then
      call SetErrStat( ErrID_Fatal, 'Cannot use unsteady aerodynamics module with a cavitation check', ErrStat, ErrMsg, RoutineName )
   end if
        
   if (InputFileData%InCol_Cpmin == 0 .and. InputFileData%CavitCheck) call SetErrStat( ErrID_Fatal, 'InCol_Cpmin must not be 0 to do a cavitation check.', ErrStat, ErrMsg, RoutineName )

         ! validate the number of airfoils
   if (InputFileData%NumAFfiles  < 1) call SetErrStat( ErrID_Fatal, 'The number of unique airfoil tables (NumAFfiles) must be greater than zero.', ErrStat, ErrMsg, RoutineName )   
   
      ! .............................
      ! check blade mesh data:
      ! .............................
   do iR = 1,size(NumBl)
      if (NumBl(iR)>0) then
         if ( InputFileData%rotors(iR)%BladeProps(1)%NumBlNds < 2 ) call SetErrStat( ErrID_Fatal, 'There must be at least two nodes per blade.',ErrStat, ErrMsg, RoutineName )
      endif
      do k=2,NumBl(iR)
         if ( InputFileData%rotors(iR)%BladeProps(k)%NumBlNds /= InputFileData%rotors(iR)%BladeProps(k-1)%NumBlNds ) then
            call SetErrStat( ErrID_Fatal, 'All blade property files must have the same number of blade nodes.', ErrStat, ErrMsg, RoutineName )
            exit  ! exit do loop
         end if
      end do
   
      ! Check the list of airfoil tables for blades to make sure they are all within limits.
      do k=1,NumBl(iR)
         do j=1,InputFileData%rotors(iR)%BladeProps(k)%NumBlNds
            if ( ( InputFileData%rotors(iR)%BladeProps(k)%BlAFID(j) < 1 ) .OR. ( InputFileData%rotors(iR)%BladeProps(k)%BlAFID(j) > InputFileData%NumAFfiles ) )  then
               call SetErrStat( ErrID_Fatal, 'Blade '//trim(Num2LStr(k))//' node '//trim(Num2LStr(j))//' must be a number between 1 and NumAFfiles (' &
                  //TRIM(Num2LStr(InputFileData%NumAFfiles))//').', ErrStat, ErrMsg, RoutineName )
            end if
         end do ! j=nodes
      end do ! k=blades
            
      ! Check that the blade chord is > 0.
      do k=1,NumBl(iR)
         do j=1,InputFileData%rotors(iR)%BladeProps(k)%NumBlNds
            if ( InputFileData%rotors(iR)%BladeProps(k)%BlChord(j) <= 0.0_ReKi )  then
               call SetErrStat( ErrID_Fatal, 'The chord for blade '//trim(Num2LStr(k))//' node '//trim(Num2LStr(j)) &
                                //' must be greater than 0.', ErrStat, ErrMsg, RoutineName )
            endif
         end do ! j=nodes
      end do ! k=blades
   
      do k=1,NumBl(iR)
         if ( .not. EqualRealNos(InputFileData%rotors(iR)%BladeProps(k)%BlSpn(1), 0.0_ReKi) ) call SetErrStat( ErrID_Fatal, 'Blade '//trim(Num2LStr(k))//' span location must start at 0.0 m', ErrStat, ErrMsg, RoutineName)       
         do j=2,InputFileData%rotors(iR)%BladeProps(k)%NumBlNds
            if ( InputFileData%rotors(iR)%BladeProps(k)%BlSpn(j) <= InputFileData%rotors(iR)%BladeProps(k)%BlSpn(j-1) )  then
               call SetErrStat( ErrID_Fatal, 'Blade '//trim(Num2LStr(k))//' nodes must be entered in increasing elevation.', ErrStat, ErrMsg, RoutineName )
               exit
            end if
         end do ! j=nodes
      end do ! k=blades
   end do ! iR rotor
   
      ! .............................
      ! check tower mesh data:
      ! .............................
   if (InputFileData%TwrPotent /= TwrPotent_none .or. InputFileData%TwrShadow /= TwrShadow_none .or. InputFileData%TwrAero ) then
      
         
         ! Check that the tower diameter is > 0.
      do iR = 1,size(NumBl)
         if (InputFileData%rotors(iR)%NumTwrNds < 2) call SetErrStat( ErrID_Fatal, 'There must be at least two nodes on the tower.',ErrStat, ErrMsg, RoutineName )
         do j=1,InputFileData%rotors(iR)%NumTwrNds
            if ( InputFileData%rotors(iR)%TwrDiam(j) <= 0.0_ReKi )  then
               call SetErrStat( ErrID_Fatal, 'The diameter for tower node '//trim(Num2LStr(j))//' must be greater than 0.' &
                               , ErrStat, ErrMsg, RoutineName )
            end if
         end do ! j=nodes
         
            ! check that the elevation is increasing:
         do j=2,InputFileData%rotors(iR)%NumTwrNds
            if ( InputFileData%rotors(iR)%TwrElev(j) <= InputFileData%rotors(iR)%TwrElev(j-1) )  then
               call SetErrStat( ErrID_Fatal, 'The tower nodes must be entered in increasing elevation.', ErrStat, ErrMsg, RoutineName )
               exit
            end if
         end do ! j=nodes
      end do ! iR rotor
            
   end if
   
      ! .............................
      ! check outputs:
      ! .............................
   
   if ( ( InputFileData%NTwOuts < 0_IntKi ) .OR. ( InputFileData%NTwOuts > 9_IntKi ) )  then
      call SetErrStat( ErrID_Fatal, 'NTwOuts must be between 0 and 9 (inclusive).', ErrStat, ErrMsg, RoutineName )
   else
         ! Check to see if all TwOutNd(:) analysis points are existing analysis points:

      do iR = 1,size(NumBl)
         do j=1,InputFileData%NTwOuts
            if ( InputFileData%TwOutNd(j) < 1_IntKi .OR. InputFileData%TwOutNd(j) > InputFileData%rotors(iR)%NumTwrNds ) then
               call SetErrStat( ErrID_Fatal, ' All TwOutNd values must be between 1 and '//&
                              trim( Num2LStr( InputFileData%rotors(iR)%NumTwrNds ) )//' (inclusive).', ErrStat, ErrMsg, RoutineName )
               exit ! stop checking this loop
            end if
         end do         
      enddo ! iR
   
   end if
         
         
   if ( ( InputFileData%NBlOuts < 0_IntKi ) .OR. ( InputFileData%NBlOuts > 9_IntKi ) )  then
      call SetErrStat( ErrID_Fatal, 'NBlOuts must be between 0 and 9 (inclusive).', ErrStat, ErrMsg, RoutineName )
   else 

   ! Check to see if all BlOutNd(:) analysis points are existing analysis points:

      do iR = 1,size(NumBl)
         do j=1,InputFileData%NBlOuts
            if ( InputFileData%BlOutNd(j) < 1_IntKi .OR. InputFileData%BlOutNd(j) > InputFileData%rotors(iR)%BladeProps(1)%NumBlNds ) then
               call SetErrStat( ErrID_Fatal, ' All BlOutNd values must be between 1 and '//&
                       trim( Num2LStr( InputFileData%rotors(iR)%BladeProps(1)%NumBlNds ) )//' (inclusive).', ErrStat, ErrMsg, RoutineName )
               exit ! stop checking this loop
            end if
         end do
      end do ! iR, rotor
      
   end if   
   
   !..................
   ! check for linearization
   !..................
   if (InitInp%Linearize) then
      if (InputFileData%AFAeroMod /= AFAeroMod_Steady) then
!bjj: REMOVE when linearization has been tested
         call SetErrStat( ErrID_Fatal, 'Steady blade airfoil aerodynamics must be used for linearization. Set AFAeroMod=1.', ErrStat, ErrMsg, RoutineName )
         !if (InputFileData%UAMod /= UA_HGM) then
         !   call SetErrStat( ErrID_Fatal, 'When AFAeroMod=2, UAMod must be 4 for linearization. Set AFAeroMod=1 or UAMod=4.', ErrStat, ErrMsg, RoutineName )
         !end if
      end if
      
      if (InputFileData%WakeMod == WakeMod_FVW) then
         call SetErrStat( ErrID_Fatal, 'FVW cannot currently be used for linearization. Set WakeMod=0 or WakeMod=1.', ErrStat, ErrMsg, RoutineName )
      else if (InputFileData%WakeMod == WakeMod_DBEMT) then
!bjj: when linearization has been tested
         call SetErrStat( ErrID_Fatal, 'DBEMT cannot currently be used for linearization. Set WakeMod=0 or WakeMod=1.', ErrStat, ErrMsg, RoutineName )
         !if (InputFileData%DBEMT_Mod /= DBEMT_cont_tauConst) then
         !   call SetErrStat( ErrID_Fatal, 'DBEMT requires the continuous formulation with constant tau1 for linearization. Set DBEMT_Mod=3 or set WakeMod to 0 or 1.', ErrStat, ErrMsg, RoutineName )
         !end if
      end if
   end if
   
END SUBROUTINE ValidateInputData
!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine sets up the data structures and initializes AirfoilInfo to get the necessary AFI parameters. It then verifies 
!! that the UA parameters are included in the AFI tables if UA is being used.
SUBROUTINE Init_AFIparams( InputFileData, p_AFI, UnEc,  ErrStat, ErrMsg )


      ! Passed variables
   type(AD_InputFile),                   intent(inout) :: InputFileData      !< All the data in the AeroDyn input file (intent(out) only because of the call to MOVE_ALLOC)
   type(AFI_ParameterType), allocatable, intent(  out) :: p_AFI(:)           !< parameters returned from the AFI (airfoil info) module
   integer(IntKi),                       intent(in   ) :: UnEc               !< I/O unit for echo file. If > 0, file is open for writing.
   integer(IntKi),                       intent(  out) :: ErrStat            !< Error status
   character(*),                         intent(  out) :: ErrMsg             !< Error message

      ! local variables
   type(AFI_InitInputType)                             :: AFI_InitInputs     ! initialization data for the AFI routines
   
   integer(IntKi)                                      :: File               ! loop counter for airfoil files
   
   integer(IntKi)                                      :: ErrStat2
   character(ErrMsgLen)                                :: ErrMsg2
   character(*), parameter                             :: RoutineName = 'Init_AFIparams'

   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   allocate(p_AFI( InputFileData%NumAFfiles), STAT = ErrStat2)
      if ( ErrStat2 /= 0 ) then
         call SetErrStat(ErrID_Fatal,'Error allocating p_AFI.',ErrStat,ErrMsg,RoutineName)
         return
      end if
   
   
      ! Setup Airfoil InitInput data structure:
   AFI_InitInputs%InCol_Alfa  = InputFileData%InCol_Alfa
   AFI_InitInputs%InCol_Cl    = InputFileData%InCol_Cl
   AFI_InitInputs%InCol_Cd    = InputFileData%InCol_Cd
   AFI_InitInputs%InCol_Cm    = InputFileData%InCol_Cm
   IF (.not. InputFileData%UseBlCm) AFI_InitInputs%InCol_Cm = 0      ! Don't try to use Cm if flag set to false
   AFI_InitInputs%InCol_Cpmin = InputFileData%InCol_Cpmin
   AFI_InitInputs%AFTabMod    = InputFileData%AFTabMod !AFITable_1
   AFI_InitInputs%UA_f_cn     = InputFileData%UAMod /= UA_HGM ! HGM uses the separation function based on cl instead of cn
   
      ! Call AFI_Init to read in and process the airfoil files.
      ! This includes creating the spline coefficients to be used for interpolation.
   
   do File = 1, InputFileData%NumAFfiles

      AFI_InitInputs%FileName = InputFileData%AFNames(File)

      call AFI_Init ( AFI_InitInputs, p_AFI(File), ErrStat2, ErrMsg2, UnEc )
         call SetErrStat(ErrStat2,ErrMsg2, ErrStat, ErrMsg, RoutineName)
         if (ErrStat >= AbortErrLev) exit
   end do
         
      
   call AFI_DestroyInitInput( AFI_InitInputs, ErrStat2, ErrMsg2 )
   if (ErrStat >= AbortErrLev) return
   
   
END SUBROUTINE Init_AFIparams
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine initializes the Airfoil Noise module from within AeroDyn.
SUBROUTINE Init_AAmodule( DrvInitInp, AD_InputFileData, RotInputFileData, u_AD, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg )
!..................................................................................................................................
   type(RotInitInputType),       intent(in   ) :: DrvInitInp    !< AeroDyn-level initialization inputs
   type(AD_InputFile),           intent(in   ) :: AD_InputFileData  !< All the data in the AeroDyn input file
   type(RotInputFile),           intent(in   ) :: RotInputFileData  !< Data in the AeroDyn input file related to current rotor
   type(RotInputType),           intent(in   ) :: u_AD           !< AD inputs - used for input mesh node positions
   type(AA_InputType),           intent(  out) :: u              !< An initial guess for the input; input mesh must be defined
   type(RotParameterType),       intent(inout) :: p              !< Parameters ! intent out b/c we set the AA parameters here
   type(AD_ParameterType),       intent(inout) :: p_AD           !< Parameters ! intent out b/c we set the AA parameters here
   type(AA_ContinuousStateType), intent(  out) :: x              !< Initial continuous states
   type(AA_DiscreteStateType),   intent(  out) :: xd             !< Initial discrete states
   type(AA_ConstraintStateType), intent(  out) :: z              !< Initial guess of the constraint states
   type(AA_OtherStateType),      intent(  out) :: OtherState     !< Initial other states
   type(AA_OutputType),          intent(  out) :: y              !< Initial system outputs (outputs are not calculated;
                                                                 !!   only the output mesh is initialized)
   type(AA_MiscVarType),         intent(  out) :: m              !< Initial misc/optimization variables
   integer(IntKi),               intent(  out) :: errStat        !< Error status of the operation
   character(*),                 intent(  out) :: errMsg         !< Error message if ErrStat /= ErrID_None
   ! Local variables
   real(DbKi)                                  :: Interval       ! Coupling interval in seconds: the rate that
                                                                 !   (1) BEMT_UpdateStates() is called in loose coupling &
                                                                 !   (2) BEMT_UpdateDiscState() is called in tight coupling.
                                                                 !   Input is the suggested time from the glue code;
                                                                 !   Output is the actual coupling interval that will be used
                                                                 !   by the glue code.
   type(AA_InitInputType)                      :: InitInp        ! Input data for initialization routine
   type(AA_InitOutputType)                     :: InitOut        ! Output for initialization routine
   integer(intKi)                              :: i              ! airfoil file index                            
   integer(intKi)                              :: j              ! node index
   integer(intKi)                              :: k              ! blade index
   integer(IntKi)                              :: ErrStat2
   character(ErrMsgLen)                        :: ErrMsg2
   character(*), parameter                     :: RoutineName = 'Init_AAmodule'
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   ! Transfer from parameters and input file to init input
   Interval                 = p_AD%DT   
   InitInp%NumBlades        = p%NumBlades
   InitInp%NumBlNds         = p%NumBlNds
   InitInp%airDens          = AD_InputFileData%AirDens 
   InitInp%kinVisc          = AD_InputFileData%KinVisc                    
   InitInp%InputFile        = AD_InputFileData%AA_InputFile
   InitInp%RootName         = p_AD%RootName
   InitInp%SpdSound         = AD_InputFileData%SpdSound
   InitInp%HubHeight        = DrvInitInp%HubPosition(3)

   ! --- Transfer of airfoil info
   ALLOCATE ( InitInp%AFInfo( size(p_AD%AFI) ), STAT=ErrStat2 )
   IF ( ErrStat2 /= 0 )  THEN
      CALL SetErrStat ( ErrID_Fatal, 'Error allocating memory for the InitInp%AFInfo array.', ErrStat2, ErrMsg2, RoutineName )
      RETURN
   ENDIF
   do i=1,size(p_AD%AFI)
      call AFI_CopyParam( p_AD%AFI(i), InitInp%AFInfo(i), MESH_NEWCOPY, errStat2, errMsg2 )
      call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   end do
  
   ! --- Allocate and set AirfoilID, chord and Span for each blades
   ! note here that each blade is required to have the same number of nodes
   call AllocAry( InitInp%BlAFID, p%NumBlNds, p%NumBlades,'InitInp%BlAFID', errStat2, ErrMsg2 )
   call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( InitInp%BlChord, p%NumBlNds, p%NumBlades, 'BlChord', errStat2, ErrMsg2 )
   call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   call AllocAry( InitInp%BlSpn,   p%NumBlNds, p%NumBlades, 'BlSpn', errStat2, ErrMsg2 )
   call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
   if (ErrStat >= AbortErrLev) then
      call cleanup()
      return
   end if
   do k = 1, p%NumBlades
      do j=1, RotInputFileData%BladeProps(k)%NumBlNds
         InitInp%BlChord(j,k)  = RotInputFileData%BladeProps(k)%BlChord(  j)
         InitInp%BlSpn  (j,k)  = RotInputFileData%BladeProps(k)%BlSpn(j)
         InitInp%BlAFID(j,k)   = RotInputFileData%BladeProps(k)%BlAFID(j)           
      end do
   end do
   
   ! --- AeroAcoustics initialization call
   call AA_Init(InitInp, u, p%AA,  x, xd, z, OtherState, y, m, Interval, InitOut, ErrStat2, ErrMsg2 )
   call SetErrStat(ErrStat2,ErrMsg2, ErrStat, ErrMsg, RoutineName)   
         
   if (.not. equalRealNos(Interval, p_AD%DT) ) then
      call SetErrStat( ErrID_Fatal, "DTAero was changed in Init_AAmodule(); this is not allowed.", ErrStat2, ErrMsg2, RoutineName)
   endif

   call Cleanup()
   
contains   

   subroutine Cleanup()
      call AA_DestroyInitInput ( InitInp, ErrStat2, ErrMsg2 )   
      call AA_DestroyInitOutput( InitOut, ErrStat2, ErrMsg2 )   
   end subroutine Cleanup
   
END SUBROUTINE Init_AAmodule
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine initializes the BEMT module from within AeroDyn.
SUBROUTINE Init_BEMTmodule( InputFileData, RotInputFileData, u_AD, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg )
!..................................................................................................................................

   type(AD_InputFile),             intent(in   ) :: InputFileData  !< All the data in the AeroDyn input file
   type(RotInputFile),             intent(in   ) :: RotInputFileData !< Data in AeroDyn input file related to current rotor
   type(RotInputType),             intent(in   ) :: u_AD           !< AD inputs - used for input mesh node positions
   type(BEMT_InputType),           intent(  out) :: u              !< An initial guess for the input; input mesh must be defined
   type(RotParameterType),         intent(inout) :: p              !< Parameters ! intent out b/c we set the BEMT parameters here
   type(AD_ParameterType),         intent(inout) :: p_AD           !< Parameters ! intent out b/c we set the BEMT parameters here
   type(BEMT_ContinuousStateType), intent(  out) :: x              !< Initial continuous states
   type(BEMT_DiscreteStateType),   intent(  out) :: xd             !< Initial discrete states
   type(BEMT_ConstraintStateType), intent(  out) :: z              !< Initial guess of the constraint states
   type(BEMT_OtherStateType),      intent(  out) :: OtherState     !< Initial other states
   type(BEMT_OutputType),          intent(  out) :: y              !< Initial system outputs (outputs are not calculated;
                                                                   !!   only the output mesh is initialized)
   type(BEMT_MiscVarType),         intent(  out) :: m              !< Initial misc/optimization variables
   integer(IntKi),                 intent(  out) :: errStat        !< Error status of the operation
   character(*),                   intent(  out) :: errMsg         !< Error message if ErrStat /= ErrID_None


      ! Local variables
   real(DbKi)                                    :: Interval       ! Coupling interval in seconds: the rate that
                                                                   !   (1) BEMT_UpdateStates() is called in loose coupling &
                                                                   !   (2) BEMT_UpdateDiscState() is called in tight coupling.
                                                                   !   Input is the suggested time from the glue code;
                                                                   !   Output is the actual coupling interval that will be used
                                                                   !   by the glue code.
   type(BEMT_InitInputType)                      :: InitInp        ! Input data for initialization routine
   type(BEMT_InitOutputType)                     :: InitOut        ! Output for initialization routine
                                                 
   integer(intKi)                                :: j              ! node index
   integer(intKi)                                :: k              ! blade index
   real(ReKi)                                    :: tmp(3), tmp_sz_y, tmp_sz
   real(ReKi)                                    :: y_hat_disk(3)
   real(ReKi)                                    :: z_hat_disk(3)
   real(ReKi)                                    :: rMax
   real(ReKi)                                    :: frac
   integer(IntKi)                                :: ErrStat2
   character(ErrMsgLen)                          :: ErrMsg2
   character(*), parameter                       :: RoutineName = 'Init_BEMTmodule'

   ! note here that each blade is required to have the same number of nodes
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   
      ! set initialization data here:   
   Interval                 = p_AD%DT   
   InitInp%numBlades        = p%NumBlades
   
   InitInp%airDens          = InputFileData%AirDens 
   InitInp%kinVisc          = InputFileData%KinVisc
   InitInp%skewWakeMod      = InputFileData%SkewMod
   InitInp%yawCorrFactor    = InputFileData%SkewModFactor
   InitInp%aTol             = InputFileData%IndToler
   InitInp%useTipLoss       = InputFileData%TipLoss
   InitInp%useHubLoss       = InputFileData%HubLoss
   InitInp%useInduction     = InputFileData%WakeMod /= WakeMod_none
   InitInp%useTanInd        = InputFileData%TanInd
   InitInp%useAIDrag        = InputFileData%AIDrag        
   InitInp%useTIDrag        = InputFileData%TIDrag  
   InitInp%numBladeNodes    = p%NumBlNds
   InitInp%numReIterations  = 1                              ! This is currently not available in the input file and is only for testing  
   InitInp%maxIndIterations = InputFileData%MaxIter 
   
   
   call AllocAry(InitInp%chord, InitInp%numBladeNodes,InitInp%numBlades,'chord',  ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)   
   call AllocAry(InitInp%AFindx,InitInp%numBladeNodes,InitInp%numBlades,'AFindx', ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)   
   call AllocAry(InitInp%zHub,                        InitInp%numBlades,'zHub',   ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call AllocAry(InitInp%zLocal,InitInp%numBladeNodes,InitInp%numBlades,'zLocal', ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)   
   call AllocAry(InitInp%rLocal,InitInp%numBladeNodes,InitInp%numBlades,'rLocal', ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)   
   call AllocAry(InitInp%zTip,                        InitInp%numBlades,'zTip',   ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      
   call AllocAry(InitInp%UAOff_innerNode,             InitInp%numBlades,'UAOff_innerNode',ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call AllocAry(InitInp%UAOff_outerNode,             InitInp%numBlades,'UAOff_outerNode',ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   
   if ( ErrStat >= AbortErrLev ) then
      call Cleanup()
      return
   end if  

   
   ! Compute zLocal, zHub, zTip, rLocal, rMax
   rMax = 0.0_ReKi
   do k=1,p%numBlades
      
      InitInp%zHub(k) = TwoNorm( u_AD%BladeRootMotion(k)%Position(:,1) - u_AD%HubMotion%Position(:,1) )  
      !if (EqualRealNos(InitInp%zHub(k),0.0_ReKi) ) &
      !   call SetErrStat( ErrID_Fatal, "zHub for blade "//trim(num2lstr(k))//" is zero.", ErrStat, ErrMsg, RoutineName)
      
      ! zLocal is the distance along blade curve -- NOTE: this is an approximation.
      InitInp%zLocal(1,k) = InitInp%zHub(k) + TwoNorm( u_AD%BladeMotion(k)%Position(:,1) - u_AD%BladeRootMotion(k)%Position(:,1) )
      do j=2,p%NumBlNds
         InitInp%zLocal(j,k) = InitInp%zLocal(j-1,k) + TwoNorm( u_AD%BladeMotion(k)%Position(:,j) - u_AD%BladeMotion(k)%Position(:,j-1) ) 
      end do !j=nodes
      
      InitInp%zTip(k) = InitInp%zLocal(p%NumBlNds,k)
      
      y_hat_disk = u_AD%HubMotion%Orientation(2,:,1)
      z_hat_disk = u_AD%HubMotion%Orientation(3,:,1)
      
      do j=1,p%NumBlNds
               ! displaced position of the jth node in the kth blade relative to the hub:
         tmp =  u_AD%BladeMotion(k)%Position(:,j)  - u_AD%HubMotion%Position(:,1) 
            ! local radius (normalized distance from rotor centerline)
         tmp_sz_y = dot_product( tmp, y_hat_disk )**2
         tmp_sz   = dot_product( tmp, z_hat_disk )**2
         InitInp%rLocal(j,k) = sqrt( tmp_sz + tmp_sz_y )
         rMax = max(rMax, InitInp%rLocal(j,k))
      end do !j=nodes   
   end do !k=blades
   
   
   InitInp%UAOff_innerNode = 0
   InitInp%UAOff_outerNode = p%NumBlNds + 1
   do k = 1,p%numBlades
      do j = 1,p%NumBlNds
         frac = InitInp%rLocal(j,k) / rMax
         if (frac < InputFileData%UAStartRad) then
            InitInp%UAOff_innerNode(k) = max(InitInp%UAOff_innerNode(k), j)
         elseif (frac > InputFileData%UAEndRad) then
            InitInp%UAOff_outerNode(k) = min(InitInp%UAOff_outerNode(k), j)
         end if
      end do
   end do
   
   
               
  do k=1,p%numBlades
     do j=1,p%NumBlNds
        InitInp%chord (j,k)  = RotInputFileData%BladeProps(k)%BlChord(j)
        InitInp%AFindx(j,k)  = RotInputFileData%BladeProps(k)%BlAFID(j)
     end do
  end do
   
   InitInp%UA_Flag       = p_AD%UA_Flag
   InitInp%UAMod         = InputFileData%UAMod
   InitInp%Flookup       = InputFileData%Flookup
   InitInp%a_s           = InputFileData%SpdSound
   InitInp%SumPrint      = InputFileData%SumPrint
   InitInp%RootName      = p%RootName
      ! remove the ".AD" from the RootName
   k = len_trim(InitInp%RootName)
   if (k>3) then
      InitInp%RootName = InitInp%RootName(1:k-3)
   end if
   
   if (InputFileData%WakeMod == WakeMod_DBEMT) then
      InitInp%DBEMT_Mod  = InputFileData%DBEMT_Mod
   else
      InitInp%DBEMT_Mod  = DBEMT_none
   end if
   InitInp%tau1_const = InputFileData%tau1_const
   
   if (ErrStat >= AbortErrLev) then
      call cleanup()
      return
   end if
   
   
   call BEMT_Init(InitInp, u, p%BEMT,  x, xd, z, OtherState, p_AD%AFI, y, m, Interval, InitOut, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2,ErrMsg2, ErrStat, ErrMsg, RoutineName)   
         
   if (.not. equalRealNos(Interval, p_AD%DT) ) &
      call SetErrStat( ErrID_Fatal, "DTAero was changed in Init_BEMTmodule(); this is not allowed.", ErrStat2, ErrMsg2, RoutineName)
   
   !m%UseFrozenWake = .FALSE. !BJJ: set this in BEMT
   
   call Cleanup()
   return
      
contains   
   subroutine Cleanup()
      call BEMT_DestroyInitInput( InitInp, ErrStat2, ErrMsg2 )   
      call BEMT_DestroyInitOutput( InitOut, ErrStat2, ErrMsg2 )   
   end subroutine Cleanup
   
END SUBROUTINE Init_BEMTmodule

!----------------------------------------------------------------------------------------------------------------------------------
!> This routine initializes the FVW module from within AeroDyn.
SUBROUTINE Init_OLAF( InputFileData, u_AD, u, p, x, xd, z, OtherState, m, ErrStat, ErrMsg )
   type(AD_InputFile),              intent(in   ) :: InputFileData  !< All the data in the AeroDyn input file
   type(AD_InputType),              intent(inout) :: u_AD           !< AD inputs - used for input mesh node positions (intent out for meshcopy)
   type(FVW_InputType),             intent(  out) :: u              !< An initial guess for the input; input mesh must be defined
   type(AD_ParameterType),          intent(inout) :: p              !< Parameters ! intent out b/c we set the FVW parameters here
   type(FVW_ContinuousStateType),   intent(  out) :: x              !< Initial continuous states
   type(FVW_DiscreteStateType),     intent(  out) :: xd             !< Initial discrete states
   type(FVW_ConstraintStateType),   intent(  out) :: z              !< Initial guess of the constraint states
   type(FVW_OtherStateType),        intent(  out) :: OtherState     !< Initial other states
   type(AD_MiscVarType),            intent(inout) :: m               !< Initial misc/optimization variables
   integer(IntKi),                  intent(  out) :: errStat        !< Error status of the operation
   character(*),                    intent(  out) :: errMsg         !< Error message if ErrStat /= ErrID_None
   ! Local variables
   real(DbKi)                                    :: Interval       ! Coupling interval in seconds: the rate that
                                                                   !   (1) FVW_UpdateStates() is called in loose coupling &
                                                                   !   (2) FVW_UpdateDiscState() is called in tight coupling.
                                                                   !   Input is the suggested time from the glue code;
                                                                   !   Output is the actual coupling interval that will be used
                                                                   !   by the glue code.
   type(FVW_InitInputType)                      :: InitInp        ! Input data for initialization routine
   type(FVW_InitOutputType)                     :: InitOut        ! Output for initialization routine
   integer(intKi)                               :: nWings         ! total number of wings
   integer(intKi)                               :: j              ! node index
   integer(intKi)                               :: iB             ! blade index
   integer(intKi)                               :: iR             ! rotor index
   integer(intKi)                               :: iW, iW_incr    ! wing index
   real(ReKi), allocatable, dimension(:)        :: rLocal   
   real(ReKi)                                   :: rMax
   real(ReKi)                                   :: frac
   real(ReKi)                                   :: tmp(3), tmp_sz_y, tmp_sz
   real(ReKi)                                   :: y_hat_disk(3)
   real(ReKi)                                   :: z_hat_disk(3)
   integer(IntKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'Init_OLAF'

   ErrStat = ErrID_None
   ErrMsg  = ""

   ! Simple inputs
   InitInp%FVWFileName    = InputFileData%FVWFileName
   InitInp%DTaero         = p%DT       ! NOTE: FVW can run a lower timestep internally

   ! Allocate wings
   nWings = 0
   do iR=1,size(p%rotors)
      nWings = nWings + p%rotors(iR)%numBlades
   end do
   allocate(InitInp%W(nWings)        , STAT = ErrStat2); ErrMsg2='Allocate W'; if(Failed()) return
   allocate(InitInp%WingsMesh(nWings), STAT = ErrStat2); ErrMsg2='Allocate Wings Mesh'; if(Failed()) return

   ! --- Inputs per wings/blades
   iW_incr=0
   do iR=1, size(p%rotors)

      InitInp%numBladeNodes  = p%rotors(iR)%numBlNds ! TODO TODO TODO per wing
      InitInp%KinVisc        = p%rotors(iR)%KinVisc
      InitInp%RootName       = p%RootName(1:len_trim(p%RootName)-2) ! Removing "AD"

      ! Blades/Wings
      do iB=1,p%rotors(iR)%numBlades
         iW=iW_incr+iB
         InitInp%W(iW)%iRotor = iR ! Indicate OLAF which wing belongs to which rotor

         call AllocAry(InitInp%W(iW)%Chord, InitInp%numBladeNodes,  'chord', ErrStat2,ErrMsg2); if(Failed()) return
         call AllocAry(InitInp%W(iW)%AFindx,InitInp%numBladeNodes,1,'AFindx',ErrStat2,ErrMsg2); if(Failed()) return


         ! Compute rLocal, rMax
         call AllocAry(rLocal, InitInp%numBladeNodes, 'rLocal', ErrStat2,ErrMsg2); if(Failed()) return
         rMax = 0.0_ReKi
         ! Distance from blade to hub axis (includes hub radius)
         y_hat_disk = u_AD%rotors(iR)%HubMotion%Orientation(2,:,1)
         z_hat_disk = u_AD%rotors(iR)%HubMotion%Orientation(3,:,1)
         do j=1,p%rotors(iR)%NumBlNds
                  ! displaced position of the jth node in the kth blade relative to the hub:
            tmp =  u_AD%rotors(iR)%BladeMotion(iB)%Position(:,j)  - u_AD%rotors(iR)%HubMotion%Position(:,1)
               ! local radius (normalized distance from rotor centerline)
            tmp_sz_y = dot_product( tmp, y_hat_disk )**2
            tmp_sz   = dot_product( tmp, z_hat_disk )**2
            rLocal(j) = sqrt( tmp_sz + tmp_sz_y )
            rMax = max(rMax, rLocal(j))
         end do !j=nodes
         ! Turn off UA at user-specified spanwise radii
         InitInp%W(iW)%UAOff_innerNode = 0
         InitInp%W(iW)%UAOff_outerNode = p%rotors(iR)%NumBlNds + 1
         do j=1,p%rotors(iR)%NumBlNds
            frac = rLocal(j) / rMax 
            if (frac < InputFileData%UAStartRad) then
               InitInp%W(iW)%UAOff_innerNode = max(InitInp%W(iW)%UAOff_innerNode, j)
            elseif (frac > InputFileData%UAEndRad) then
               InitInp%W(iW)%UAOff_outerNode = min(InitInp%W(iW)%UAOff_outerNode, j)
            end if
         end do
         if(allocated(rLocal))deallocate(rLocal)

         ! Copy over chord information
         do j=1,p%rotors(iR)%NumBlNds
            InitInp%W(iW)%Chord (j)    = InputFileData%rotors(iR)%BladeProps(iB)%BlChord(j)
            InitInp%W(iW)%AFindx(j,1)  = InputFileData%rotors(iR)%BladeProps(iB)%BlAFID(j)
         end do

         ! Copy the mesh over for InitInp to FVW.  We would not need to copy this if we decided to break the Framework
         !  by passing u_AD%BladeMotion directly into FVW_Init, but nothing is really gained by doing that.
         call MeshCopy ( SrcMesh  = u_AD%rotors(iR)%BladeMotion(iB)  &
                        ,DestMesh = InitInp%WingsMesh(iW) &
                        ,CtrlCode = MESH_COUSIN         &
                        ,Orientation    = .TRUE.        &
                        ,TranslationVel = .TRUE.        &
                        ,RotationVel    = .TRUE.        &
                        ,ErrStat  = ErrStat2          &
                        ,ErrMess  = ErrMsg2          )
         if(Failed()) return
   
      enddo ! iB, blades

      ! Unsteady Aero Data
      InitInp%UA_Flag    = p%UA_Flag
      InitInp%UAMod      = InputFileData%UAMod
      InitInp%Flookup    = InputFileData%Flookup
      InitInp%a_s        = InputFileData%SpdSound
      InitInp%SumPrint   = InputFileData%SumPrint

      iW_incr = iW_incr+p%rotors(iR)%numBlades
   enddo ! iR, rotors 

   ! NOTE: not passing p%AFI at present.  We are not storing it in FVW's parameters.
   call FVW_Init(p%AFI, InitInp, u, p%FVW, x, xd, z, OtherState, m%FVW_y, m%FVW, Interval, InitOut, ErrStat2, ErrMsg2 ); if(Failed()) return

   ! set the size of the input and xd arrays for passing wind info to FVW.
   call AllocAry(u_AD%InflowWakeVel, 3, size(m%FVW%r_wind,DIM=2), 'InflowWakeVel',  ErrStat2,ErrMsg2); if(Failed()) return

   if (.not. equalRealNos(Interval, p%DT) ) then
      errStat2=ErrID_Fatal; errMsg2="DTAero was changed in Init_FVWmodule(); this is not allowed yet."; if(Failed()) return
   endif

   call CleanUp()

contains
   subroutine Cleanup()
      call FVW_DestroyInitInput(  InitInp, ErrStat2, ErrMsg2 )
      call FVW_DestroyInitOutput( InitOut, ErrStat2, ErrMsg2 )
      if(allocated(rLocal))deallocate(rLocal)
   end subroutine Cleanup

   logical function Failed()
        call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'Init_OLAF') 
        Failed =  ErrStat >= AbortErrLev
        if (Failed) call CleanUp()
   end function Failed
END SUBROUTINE Init_OLAF
!----------------------------------------------------------------------------------------------------------------------------------
!> This subroutine calculates the tower loads for the AeroDyn TowerLoad output mesh.
SUBROUTINE ADTwr_CalcOutput(p, u, m, y, ErrStat, ErrMsg )

   TYPE(RotInputType),           INTENT(IN   )  :: u           !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p           !< Parameters
   TYPE(RotMiscVarType),         INTENT(INOUT)  :: m           !< Misc/optimization variables
   TYPE(RotOutputType),          INTENT(INOUT)  :: y           !< Outputs computed at t (Input only so that mesh con-
                                                               !!   nectivity information does not have to be recalculated)
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      !< Error message if ErrStat /= ErrID_None


   INTEGER(IntKi)                               :: j
   real(ReKi)                                   :: q
   real(ReKi)                                   :: V_rel(3)    ! relative wind speed on a tower node
   real(ReKi)                                   :: VL(2)       ! relative local x- and y-components of the wind speed on a tower node
   real(ReKi)                                   :: tmp(3)
   
   !integer(intKi)                               :: ErrStat2
   !character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'ADTwr_CalcOutput'
   
   
   ErrStat = ErrID_None
   ErrMsg  = ""

   
   do j=1,p%NumTwrNds
      
      V_rel = u%InflowOnTower(:,j) - u%TowerMotion%TranslationVel(:,j) ! relative wind speed at tower node
   
      tmp   = u%TowerMotion%Orientation(1,:,j)
      VL(1) = dot_product( V_Rel, tmp )            ! relative local x-component of wind speed of the jth node in the tower
      tmp   = u%TowerMotion%Orientation(2,:,j)
      VL(2) = dot_product( V_Rel, tmp )            ! relative local y-component of wind speed of the jth node in the tower
      
      m%W_Twr(j)  =  TwoNorm( VL )            ! relative wind speed normal to the tower at node j      
      q     = 0.5 * p%TwrCd(j) * p%AirDens * p%TwrDiam(j) * m%W_Twr(j)
      
         ! force per unit length of the jth node in the tower
      tmp(1) = q * VL(1)
      tmp(2) = q * VL(2)
      tmp(3) = 0.0_ReKi
      
      y%TowerLoad%force(:,j) = matmul( tmp, u%TowerMotion%Orientation(:,:,j) ) ! note that I'm calculating the transpose here, which is okay because we have 1-d arrays
      m%X_Twr(j) = tmp(1)
      m%Y_Twr(j) = tmp(2)
      
      
         ! moment per unit length of the jth node in the tower
      y%TowerLoad%moment(:,j) = 0.0_ReKi
      
   end do
   

END SUBROUTINE ADTwr_CalcOutput
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine checks for invalid inputs to the tower influence models.
SUBROUTINE CheckTwrInfl(u, ErrStat, ErrMsg )

   TYPE(RotInputType),           INTENT(IN   )  :: u           !< Inputs at Time t
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      !< Error message if ErrStat /= ErrID_None
   
   ! local variables
   real(reKi)                                   :: ElemSize
   real(reKi)                                   :: tmp(3)
   integer(intKi)                               :: j
   character(*), parameter                      :: RoutineName = 'CheckTwrInfl'
   
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   !! the tower-influence models (tower potential flow and tower shadow) are valid only for small tower deflections;
   !! so, first throw an error to avoid a division-by-zero error if any line2 elements on the tower mesh are colocated.
   
   do j = 2,u%TowerMotion%Nnodes
      tmp =   u%TowerMotion%Position(:,j  ) + u%TowerMotion%TranslationDisp(:,j  ) &
            - u%TowerMotion%Position(:,j-1) - u%TowerMotion%TranslationDisp(:,j-1)
   
      ElemSize = TwoNorm(tmp)
      if ( EqualRealNos(ElemSize,0.0_ReKi) ) then
         call SetErrStat(ErrID_Fatal, "Division by zero:Elements "//trim(num2lstr(j))//' and '//trim(num2lstr(j-1))//' are colocated.', ErrStat, ErrMsg, RoutineName )
         exit
      end if
   end do
      
   
END SUBROUTINE CheckTwrInfl
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine calculates m%DisturbedInflow, the influence of tower shadow and/or potential flow on the inflow velocities
SUBROUTINE TwrInfl( p, u, m, ErrStat, ErrMsg )
!..................................................................................................................................

   TYPE(RotInputType),           INTENT(IN   )  :: u                       !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p                       !< Parameters
   type(RotMiscVarType),         intent(inout)  :: m                       !< Misc/optimization variables
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat                 !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg                  !< Error message if ErrStat /= ErrID_None

   ! local variables
   real(ReKi)                                   :: xbar                    ! local x^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: ybar                    ! local y^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: zbar                    ! local z^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: theta_tower_trans(3,3)  ! transpose of local tower orientation expressed as a DCM
   real(ReKi)                                   :: TwrCd                   ! local tower drag coefficient
   real(ReKi)                                   :: TwrTI                   ! local tower TI (for Eames tower shadow model) 
   real(ReKi)                                   :: W_tower                 ! local relative wind speed normal to the tower

   real(ReKi)                                   :: BladeNodePosition(3)    ! local blade node position
   
   
   real(ReKi)                                   :: u_TwrShadow             ! axial velocity deficit fraction from tower shadow
   real(ReKi)                                   :: u_TwrPotent             ! axial velocity deficit fraction from tower potential flow
   real(ReKi)                                   :: v_TwrPotent             ! transverse velocity deficit fraction from tower potential flow
   
   real(ReKi)                                   :: denom                   ! denominator
   real(ReKi)                                   :: exponential             ! exponential term
   real(ReKi)                                   :: v(3)                    ! temp vector
   
   integer(IntKi)                               :: j, k                    ! loop counters for elements, blades
   integer(intKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'TwrInfl'
   
   
   ErrStat = ErrID_None
   ErrMsg  = ""   
   
   
      ! these models are valid for only small tower deflections; check for potential division-by-zero errors:   
   call CheckTwrInfl( u, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
      if (ErrStat >= AbortErrLev) return
      
   do k = 1, p%NumBlades
      do j = 1, u%BladeMotion(k)%NNodes
         
         ! for each line2-element node of the blade mesh, a nearest-neighbor line2 element or node of the tower 
         ! mesh is found in the deflected configuration, returning theta_tower, W_tower, xbar, ybar, zbar, and TowerCd:
         
         BladeNodePosition = u%BladeMotion(k)%Position(:,j) + u%BladeMotion(k)%TranslationDisp(:,j)
         
         call getLocalTowerProps(p, u, BladeNodePosition, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, m%TwrClrnc(j,k), ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
            if (ErrStat >= AbortErrLev) return
         
      
         ! calculate tower influence:
         if ( abs(zbar) < 1.0_ReKi .and. p%TwrPotent /= TwrPotent_none ) then
            if ( p%TwrPotent == TwrPotent_baseline ) then
               
               denom = (xbar**2 + ybar**2)**2
               
               if (equalRealNos(denom,0.0_ReKi)) then
                  u_TwrPotent = 0.0_ReKi
                  v_TwrPotent = 0.0_ReKi
               else
                  u_TwrPotent = ( -1.0*xbar**2 + ybar**2 ) / denom
                  v_TwrPotent = ( -2.0*xbar    * ybar    ) / denom
               end if
               
            elseif (p%TwrPotent == TwrPotent_Bak) then
               
               xbar = xbar + 0.1
               
               denom = (xbar**2 + ybar**2)**2
               if (equalRealNos(denom,0.0_ReKi)) then
                  u_TwrPotent = 0.0_ReKi
                  v_TwrPotent = 0.0_ReKi
               else
                  u_TwrPotent = ( -1.0*xbar**2 + ybar**2 ) / denom
                  v_TwrPotent = ( -2.0*xbar    * ybar    ) / denom
               
                  denom = TwoPi*(xbar**2 + ybar**2)
                  u_TwrPotent = u_TwrPotent + TwrCd*xbar / denom
                  v_TwrPotent = v_TwrPotent + TwrCd*ybar / denom
               end if
               
            end if
         else
            u_TwrPotent = 0.0_ReKi
            v_TwrPotent = 0.0_ReKi
         end if
         
         u_TwrShadow = 0.0_ReKi
         select case (p%TwrShadow)
            case (TwrShadow_Powles)
               if ( xbar > 0.0_ReKi .and. abs(zbar) < 1.0_ReKi) then
                  denom = sqrt( sqrt( xbar**2 + ybar**2 ) )
                  if ( abs(ybar) < denom ) then
                     u_TwrShadow = -TwrCd / denom * cos( PiBy2*ybar / denom )**2
                  end if
               end if
             case (TwrShadow_Eames)
               if ( xbar > 0.0_ReKi .and. abs(zbar) < 1.0_ReKi) then
                  exponential = ( ybar / (TwrTI * xbar) )**2
                  denom = TwrTI * xbar * sqrt( TwoPi )
                  u_TwrShadow = -TwrCd / denom * exp ( -0.5_ReKi * exponential ) 
               end if
         end select
                     
         v(1) = (u_TwrPotent + u_TwrShadow)*W_tower
         v(2) = v_TwrPotent*W_tower
         v(3) = 0.0_ReKi
         
         m%DisturbedInflow(:,j,k) = u%InflowOnBlade(:,j,k) + matmul( theta_tower_trans, v ) 
      
      end do !j=NumBlNds
   end do ! NumBlades
   
   
END SUBROUTINE TwrInfl 
!----------------------------------------------------------------------------------------------------------------------------------
!> Calculate the tower influence on a array of points `Positions` (3xn)
!! The subroutine has side effecs and modifies the inflow 
!! Relies heavily (i.e. unfortunate copy pasting), on TwrInfl 
SUBROUTINE TwrInflArray( p, u, m, Positions, Inflow, ErrStat, ErrMsg )
   TYPE(RotInputType),           INTENT(IN   )  :: u                       !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p                       !< Parameters
   type(RotMiscVarType),         intent(inout)  :: m                       !< Misc/optimization variables
   real(ReKi), dimension(:,:),   INTENT(IN   )  :: Positions               !< Positions where tower influence is to be computed
   real(ReKi), dimension(:,:),   INTENT(INOUT)  :: Inflow                  !< Undisturbed inflow (in) -> disturbed inflow (out)
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat                 !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg                  !< Error message if ErrStat /= ErrID_None
   ! local variables
   real(ReKi)                                   :: xbar                    ! local x^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: ybar                    ! local y^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: zbar                    ! local z^ component of r_TowerBlade (distance from tower to blade) normalized by tower radius
   real(ReKi)                                   :: theta_tower_trans(3,3)  ! transpose of local tower orientation expressed as a DCM
   real(ReKi)                                   :: TwrCd                   ! local tower drag coefficient
   real(ReKi)                                   :: TwrTI                   ! local tower TI (for Eames tower shadow model)
   real(ReKi)                                   :: W_tower                 ! local relative wind speed normal to the tower
   real(ReKi)                                   :: Pos(3)                  ! current point
   real(ReKi)                                   :: u_TwrShadow             ! axial velocity deficit fraction from tower shadow
   real(ReKi)                                   :: u_TwrPotent             ! axial velocity deficit fraction from tower potential flow
   real(ReKi)                                   :: v_TwrPotent             ! transverse velocity deficit fraction from tower potential flow
   real(ReKi)                                   :: denom                   ! denominator
   real(ReKi)                                   :: exponential             ! exponential term
   real(ReKi)                                   :: v(3)                    ! temp vector
   integer(IntKi)                               :: i                       ! loop counters for points
   real(ReKi)                                   :: TwrClrnc                ! local tower clearance
   real(ReKi)                                   :: r_TowerBlade(3)         ! distance vector from tower to blade
   real(ReKi)                                   :: TwrDiam                 ! local tower diameter  
   logical                                      :: found   
   integer(intKi)                               :: ErrStat2
   character(ErrMsgLen)                         :: ErrMsg2
   character(*), parameter                      :: RoutineName = 'TwrInflArray'
   ErrStat = ErrID_None
   ErrMsg  = ""   
   
   ! these models are valid for only small tower deflections; check for potential division-by-zero errors:   
   call CheckTwrInfl( u, ErrStat2, ErrMsg2 ); call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName ); if (ErrStat >= AbortErrLev) return

   !$OMP PARALLEL default(shared)
   !$OMP do private(i,Pos,r_TowerBlade,theta_tower_trans,W_tower,xbar,ybar,zbar,TwrCd,TwrTI,TwrClrnc,TwrDiam,found,denom,exponential,u_TwrPotent,v_TwrPotent,u_TwrShadow,v) schedule(runtime)
   do i = 1, size(Positions,2)
      Pos=Positions(1:3,i)
         
      ! Find nearest line2 element or node of the tower  (see getLocalTowerProps)
      ! values are found for the deflected tower, returning theta_tower, W_tower, xbar, ybar, zbar, and TowerCd:
      ! option 1: nearest line2 element
      call TwrInfl_NearestLine2Element(p, u, Pos, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam, found)
      if ( .not. found) then 
         ! option 2: nearest node
         call TwrInfl_NearestPoint(p, u, Pos, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam)
      end if
      TwrClrnc = TwoNorm(r_TowerBlade) - 0.5_ReKi*TwrDiam

      if ( TwrClrnc>20*TwrDiam) then
         ! Far away, we skip the computation and keep undisturbed inflow 
      elseif ( TwrClrnc<=0.01_ReKi*TwrDiam) then
         ! Inside the tower, or very close, (will happen for vortex elements) we keep undisturbed inflow
         ! We don't want to reach the stagnation points
      else
         ! calculate tower influence:
         if ( abs(zbar) < 1.0_ReKi .and. p%TwrPotent /= TwrPotent_none ) then

            if ( p%TwrPotent == TwrPotent_baseline ) then
               denom = (xbar**2 + ybar**2)**2
               u_TwrPotent = ( -1.0*xbar**2 + ybar**2 ) / denom
               v_TwrPotent = ( -2.0*xbar    * ybar    ) / denom      

            elseif (p%TwrPotent == TwrPotent_Bak) then
               xbar = xbar + 0.1
               denom = (xbar**2 + ybar**2)**2               
               u_TwrPotent = ( -1.0*xbar**2 + ybar**2 ) / denom
               v_TwrPotent = ( -2.0*xbar    * ybar    ) / denom        
               denom = TwoPi*(xbar**2 + ybar**2)               
               u_TwrPotent = u_TwrPotent + TwrCd*xbar / denom
               v_TwrPotent = v_TwrPotent + TwrCd*ybar / denom                       
               
            end if
         else
            u_TwrPotent = 0.0_ReKi
            v_TwrPotent = 0.0_ReKi
         end if
         
         u_TwrShadow = 0.0_ReKi
         select case (p%TwrShadow)
            case (TwrShadow_Powles)
               if ( xbar > 0.0_ReKi .and. abs(zbar) < 1.0_ReKi) then
                  denom = sqrt( sqrt( xbar**2 + ybar**2 ) )
                  if ( abs(ybar) < denom ) then
                     u_TwrShadow = -TwrCd / denom * cos( PiBy2*ybar / denom )**2
                  end if
               end if
             case (TwrShadow_Eames)
               if ( xbar > 0.0_ReKi .and. abs(zbar) < 1.0_ReKi) then
                  exponential = ( ybar / (TwrTI * xbar) )**2
                  denom = TwrTI * xbar * sqrt( TwoPi )
                  u_TwrShadow = -TwrCd / denom * exp ( -0.5_ReKi * exponential ) 
               end if
            ! We limit the deficit to avoid having too much flow reversal and accumulation of vorticity behind the tower
            ! Limit to -0.5 the wind speed at the tower
            u_TwrShadow =max(u_TwrShadow, -0.5)
         end select
                     
         v(1) = (u_TwrPotent + u_TwrShadow)*W_tower
         v(2) = v_TwrPotent*W_tower
         v(3) = 0.0_ReKi
         
         Inflow(1:3,i) = Inflow(1:3,i) + matmul( theta_tower_trans, v ) 
      endif ! Check if point far away or in tower
   enddo ! loop on points
   !$OMP END DO 
   !$OMP END PARALLEL
END SUBROUTINE TwrInflArray
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine returns the tower constants necessary to compute the tower influence. 
!! if u%TowerMotion does not have any nodes there will be serious problems. I assume that has been checked earlier.
SUBROUTINE getLocalTowerProps(p, u, BladeNodePosition, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrClrnc, ErrStat, ErrMsg)
!..................................................................................................................................
   TYPE(RotInputType),           INTENT(IN   )  :: u                       !< Inputs at Time t
   TYPE(RotParameterType),       INTENT(IN   )  :: p                       !< Parameters
   REAL(ReKi)                   ,INTENT(IN   )  :: BladeNodePosition(3)    !< local blade node position
   REAL(ReKi)                   ,INTENT(  OUT)  :: theta_tower_trans(3,3)  !< transpose of local tower orientation expressed as a DCM
   REAL(ReKi)                   ,INTENT(  OUT)  :: W_tower                 !< local relative wind speed normal to the tower
   REAL(ReKi)                   ,INTENT(  OUT)  :: xbar                    !< local x^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                   ,INTENT(  OUT)  :: ybar                    !< local y^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                   ,INTENT(  OUT)  :: zbar                    !< local z^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                   ,INTENT(  OUT)  :: TwrCd                   !< local tower drag coefficient
   REAL(ReKi)                   ,INTENT(  OUT)  :: TwrTI                   !< local tower TI (for Eames tower shadow model)
   REAL(ReKi)                   ,INTENT(  OUT)  :: TwrClrnc                !< tower clearance for potential output 
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat                 !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg                  !< Error message if ErrStat /= ErrID_None

   ! local variables
   real(ReKi)                                   :: r_TowerBlade(3)         ! distance vector from tower to blade
   real(ReKi)                                   :: TwrDiam                 ! local tower diameter  
   logical                                      :: found   
   character(*), parameter                      :: RoutineName = 'getLocalTowerProps'
   
   
   ErrStat = ErrID_None
   ErrMsg  = ""   
   
   ! ..............................................
   ! option 1: nearest line2 element
   ! ..............................................
   call TwrInfl_NearestLine2Element(p, u, BladeNodePosition, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam, found)
   
   if ( .not. found) then 
      ! ..............................................
      ! option 2: nearest node
      ! ..............................................
      call TwrInfl_NearestPoint(p, u, BladeNodePosition, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam)
         
   end if
   
   TwrClrnc = TwoNorm(r_TowerBlade) - 0.5_ReKi*TwrDiam
   if ( TwrClrnc <= 0.0_ReKi ) then
      call SetErrStat(ErrID_Fatal, "Tower strike.", ErrStat, ErrMsg, RoutineName)
   end if
   
   
END SUBROUTINE getLocalTowerProps
!----------------------------------------------------------------------------------------------------------------------------------
!> Option 1: Find the nearest-neighbor line2 element of the tower mesh for which the blade line2-element node projects orthogonally onto
!!   the tower line2-element domain (following an approach similar to the line2_to_line2 mapping search for motion and scalar quantities). 
!!   That is, for each node of the blade mesh, an orthogonal projection is made onto all possible Line2 elements of the tower mesh and 
!!   the line2 element of the tower mesh that is the minimum distance away is found.
!! Adapted from modmesh_mapping::createmapping_projecttoline2()
SUBROUTINE TwrInfl_NearestLine2Element(p, u, BladeNodePosition, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam, found)
!..................................................................................................................................
   TYPE(RotInputType),              INTENT(IN   )  :: u                             !< Inputs at Time t
   TYPE(RotParameterType),          INTENT(IN   )  :: p                             !< Parameters
   REAL(ReKi)                      ,INTENT(IN   )  :: BladeNodePosition(3)          !< local blade node position
   REAL(ReKi)                      ,INTENT(  OUT)  :: r_TowerBlade(3)               !< distance vector from tower to blade
   REAL(ReKi)                      ,INTENT(  OUT)  :: theta_tower_trans(3,3)        !< transpose of local tower orientation expressed as a DCM
   REAL(ReKi)                      ,INTENT(  OUT)  :: W_tower                       !< local relative wind speed normal to the tower
   REAL(ReKi)                      ,INTENT(  OUT)  :: xbar                          !< local x^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: ybar                          !< local y^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: zbar                          !< local z^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrCd                         !< local tower drag coefficient
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrTI                         !< local tower TI (Eames tower shadow model) 
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrDiam                       !< local tower diameter
   logical                         ,INTENT(  OUT)  :: found                         !< whether a mapping was found with this option 
      
      ! local variables
   REAL(ReKi)      :: denom
   REAL(ReKi)      :: dist
   REAL(ReKi)      :: min_dist
   REAL(ReKi)      :: elem_position, elem_position2
   REAL(SiKi)      :: elem_position_SiKi

   REAL(ReKi)      :: p1(3), p2(3)        ! position vectors for nodes on tower line 2 element
   
   REAL(ReKi)      :: V_rel_tower(3)
   
   REAL(ReKi)      :: n1_n2_vector(3)     ! vector going from node 1 to node 2 in Line2 element
   REAL(ReKi)      :: n1_Point_vector(3)  ! vector going from node 1 in Line 2 element to Destination Point
   REAL(ReKi)      :: tmp(3)              ! temporary vector for cross product calculation

   INTEGER(IntKi)  :: jElem               ! do-loop counter for elements on tower mesh

   INTEGER(IntKi)  :: n1, n2              ! nodes associated with an element

   LOGICAL         :: on_element
   
      
   found = .false.
   min_dist = HUGE(min_dist)

   do jElem = 1, u%TowerMotion%ElemTable(ELEMENT_LINE2)%nelem   ! number of elements on TowerMesh
         ! grab node numbers associated with the jElem_th element
      n1 = u%TowerMotion%ElemTable(ELEMENT_LINE2)%Elements(jElem)%ElemNodes(1)
      n2 = u%TowerMotion%ElemTable(ELEMENT_LINE2)%Elements(jElem)%ElemNodes(2)

      p1 = u%TowerMotion%Position(:,n1) + u%TowerMotion%TranslationDisp(:,n1)
      p2 = u%TowerMotion%Position(:,n2) + u%TowerMotion%TranslationDisp(:,n2)

         ! Calculate vectors used in projection operation
      n1_n2_vector    = p2 - p1
      n1_Point_vector = BladeNodePosition - p1

      denom           = DOT_PRODUCT( n1_n2_vector, n1_n2_vector ) ! we've already checked that these aren't zero

         ! project point onto line defined by n1 and n2

      elem_position = DOT_PRODUCT(n1_n2_vector,n1_Point_vector) / denom

            ! note: i forumlated it this way because Fortran doesn't necessarially do shortcutting and I don't want to call EqualRealNos if we don't need it:
      if ( elem_position .ge. 0.0_ReKi .and. elem_position .le. 1.0_ReKi ) then !we're ON the element (between the two nodes)
         on_element = .true.
      else
         elem_position_SiKi = REAL( elem_position, SiKi )
         if (EqualRealNos( elem_position_SiKi, 1.0_SiKi )) then !we're ON the element (at a node)
            on_element = .true.
            elem_position = 1.0_ReKi
         elseif (EqualRealNos( elem_position_SiKi,  0.0_SiKi )) then !we're ON the element (at a node)
            on_element = .true.
            elem_position = 0.0_ReKi
         else !we're not on the element
            on_element = .false.
         end if
         
      end if

      if (on_element) then

         ! calculate distance between point and line (note: this is actually the distance squared);
         ! will only store information once we have determined the closest element
         elem_position2 = 1.0_ReKi - elem_position
         
         r_TowerBlade  = BladeNodePosition - elem_position2*p1 - elem_position*p2
         dist = dot_product( r_TowerBlade, r_TowerBlade )

         if (dist .lt. min_dist) then
            found = .true.
            min_dist = dist

            V_rel_tower =   ( u%InflowOnTower(:,n1) - u%TowerMotion%TranslationVel(:,n1) ) * elem_position2  &
                          + ( u%InflowOnTower(:,n2) - u%TowerMotion%TranslationVel(:,n2) ) * elem_position
            
            TwrDiam     = elem_position2*p%TwrDiam(n1) + elem_position*p%TwrDiam(n2)
            TwrCd       = elem_position2*p%TwrCd(  n1) + elem_position*p%TwrCd(  n2)
            TwrTI       = elem_position2*p%TwrTI(  n1) + elem_position*p%TwrTI(  n2)
            
            
            ! z_hat
            theta_tower_trans(:,3) = n1_n2_vector / sqrt( denom ) ! = n1_n2_vector / twoNorm( n1_n2_vector )
            
            tmp = V_rel_tower - dot_product(V_rel_tower,theta_tower_trans(:,3)) * theta_tower_trans(:,3)
            denom = TwoNorm( tmp )
            if (.not. EqualRealNos( denom, 0.0_ReKi ) ) then
               ! x_hat
               theta_tower_trans(:,1) = tmp / denom
               
               ! y_hat
               tmp = cross_product( theta_tower_trans(:,3), V_rel_tower )
               theta_tower_trans(:,2) = tmp / denom  
               
               W_tower = dot_product( V_rel_tower,theta_tower_trans(:,1) )
               xbar    = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,1) )
               ybar    = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,2) )
               zbar    = 0.0_ReKi
                                             
            else
                  ! there is no tower influence because dot_product(V_rel_tower,x_hat) = 0
                  ! thus, we don't need to set the other values (except we don't want the sum of xbar^2 and ybar^2 to be 0)
               theta_tower_trans = 0.0_ReKi
               W_tower           = 0.0_ReKi
               xbar              = 1.0_ReKi
               ybar              = 0.0_ReKi  
               zbar              = 0.0_ReKi
            end if
   
            
         end if !the point is closest to this line2 element

      end if

   end do !jElem

END SUBROUTINE TwrInfl_NearestLine2Element
!----------------------------------------------------------------------------------------------------------------------------------
!> Option 2: used when the blade node does not orthogonally intersect a tower element.
!!  Find the nearest-neighbor node in the tower Line2-element domain (following an approach similar to the point_to_point mapping
!!  search for motion and scalar quantities). That is, for each node of the blade mesh, the node of the tower mesh that is the minimum 
!!  distance away is found.
SUBROUTINE TwrInfl_NearestPoint(p, u, BladeNodePosition, r_TowerBlade, theta_tower_trans, W_tower, xbar, ybar, zbar, TwrCd, TwrTI, TwrDiam)
!..................................................................................................................................
   TYPE(RotInputType),              INTENT(IN   )  :: u                             !< Inputs at Time t
   TYPE(RotParameterType),          INTENT(IN   )  :: p                             !< Parameters
   REAL(ReKi)                      ,INTENT(IN   )  :: BladeNodePosition(3)          !< local blade node position
   REAL(ReKi)                      ,INTENT(  OUT)  :: r_TowerBlade(3)               !< distance vector from tower to blade
   REAL(ReKi)                      ,INTENT(  OUT)  :: theta_tower_trans(3,3)        !< transpose of local tower orientation expressed as a DCM
   REAL(ReKi)                      ,INTENT(  OUT)  :: W_tower                       !< local relative wind speed normal to the tower
   REAL(ReKi)                      ,INTENT(  OUT)  :: xbar                          !< local x^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: ybar                          !< local y^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: zbar                          !< local z^ component of r_TowerBlade normalized by tower radius
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrCd                         !< local tower drag coefficient
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrTI                         !< local tower TI (for Eeames tower shadow model)
   REAL(ReKi)                      ,INTENT(  OUT)  :: TwrDiam                       !< local tower diameter
      
      ! local variables
   REAL(ReKi)      :: denom
   REAL(ReKi)      :: dist
   REAL(ReKi)      :: min_dist
   REAL(ReKi)      :: cosTaper

   REAL(ReKi)      :: p1(3)                     ! position vectors for nodes on tower   
   REAL(ReKi)      :: V_rel_tower(3)
   
   REAL(ReKi)      :: tmp(3)                    ! temporary vector for cross product calculation

   INTEGER(IntKi)  :: n1                        ! node
   INTEGER(IntKi)  :: node_with_min_distance    

   
   
      !.................
      ! find the closest node
      !.................
      
   min_dist = HUGE(min_dist)
   node_with_min_distance = 0

   do n1 = 1, u%TowerMotion%NNodes   ! number of nodes on TowerMesh
      
      p1 = u%TowerMotion%Position(:,n1) + u%TowerMotion%TranslationDisp(:,n1)
      
         ! calculate distance between points (note: this is actually the distance squared);
         ! will only store information once we have determined the closest node
      r_TowerBlade  = BladeNodePosition - p1         
      dist = dot_product( r_TowerBlade, r_TowerBlade )

      if (dist .lt. min_dist) then
         min_dist = dist
         node_with_min_distance = n1
               
      end if !the point is (so far) closest to this blade node

   end do !n1
   
      !.................
      ! calculate the values to be returned:  
      !..................
   if (node_with_min_distance == 0) then
      node_with_min_distance = 1
      if (NWTC_VerboseLevel == NWTC_Verbose) call WrScr( 'AD:TwrInfl_NearestPoint:Error finding minimum distance. Positions may be invalid.' )
   end if
   
   n1 = node_with_min_distance
   
   r_TowerBlade = BladeNodePosition - u%TowerMotion%Position(:,n1) - u%TowerMotion%TranslationDisp(:,n1)
   V_rel_tower  = u%InflowOnTower(:,n1) - u%TowerMotion%TranslationVel(:,n1)
   TwrDiam      = p%TwrDiam(n1) 
   TwrCd        = p%TwrCd(  n1) 
   TwrTI        = p%TwrTI(  n1) 
                           
   ! z_hat
   theta_tower_trans(:,3) = u%TowerMotion%Orientation(3,:,n1)
            
   tmp = V_rel_tower - dot_product(V_rel_tower,theta_tower_trans(:,3)) * theta_tower_trans(:,3)
   denom = TwoNorm( tmp )
   
   if (.not. EqualRealNos( denom, 0.0_ReKi ) ) then
      
      ! x_hat
      theta_tower_trans(:,1) = tmp / denom
               
      ! y_hat
      tmp = cross_product( theta_tower_trans(:,3), V_rel_tower )
      theta_tower_trans(:,2) = tmp / denom  
               
      W_tower = dot_product( V_rel_tower,theta_tower_trans(:,1) )

      if ( n1 == 1 .or. n1 == u%TowerMotion%NNodes) then         
         ! option 2b
         zbar    = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,3) )
         if (abs(zbar) < 1) then   
            cosTaper = cos( PiBy2*zbar )
            xbar = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,1) ) / cosTaper
            ybar = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,2) ) / cosTaper
         else ! we check that zbar < 1 before using xbar and ybar later, but I'm going to set them here anyway:
            xbar = 1.0_ReKi
            ybar = 0.0_ReKi  
         end if                                    
      else
         ! option 2a
         xbar    = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,1) )
         ybar    = 2.0/TwrDiam * dot_product( r_TowerBlade, theta_tower_trans(:,2) )
         zbar    = 0.0_ReKi
      end if

   else
      
         ! there is no tower influence because W_tower = dot_product(V_rel_tower,x_hat) = 0
         ! thus, we don't need to set the other values (except we don't want the sum of xbar^2 and ybar^2 to be 0)
      W_tower           = 0.0_ReKi
      theta_tower_trans = 0.0_ReKi
      xbar              = 1.0_ReKi
      ybar              = 0.0_ReKi  
      zbar              = 0.0_ReKi
      
   end if   

END SUBROUTINE TwrInfl_NearestPoint
!----------------------------------------------------------------------------------------------------------------------------------

!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! ###### The following four routines are Jacobian routines for linearization capabilities #######
! If the module does not implement them, set ErrStat = ErrID_Fatal in AD_Init() when InitInp%Linearize is .true.
!----------------------------------------------------------------------------------------------------------------------------------
!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the inputs (u). The partial derivatives dY/du, dX/du, dXd/du, and dZ/du are returned.
SUBROUTINE AD_JacobianPInput( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdu, dXdu, dXddu, dZdu)
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(AD_InputType),                   INTENT(INOUT)           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(AD_DiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(AD_ConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(AD_OtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(AD_OutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdu.
   TYPE(AD_MiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdu(:,:)  !< Partial derivatives of output functions (Y) with respect
                                                                               !!   to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdu(:,:)  !< Partial derivatives of continuous state functions (X) with
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddu(:,:) !< Partial derivatives of discrete state functions (Xd) with
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdu(:,:)  !< Partial derivatives of constraint state functions (Z) with
   !
   integer(IntKi), parameter :: iR =1 ! Rotor index

   if (size(p%rotors)>1) then
      errStat = ErrID_Fatal
      errMsg = 'Linearization with more than one rotor not supported'
      return
   endif

   call Rot_JacobianPInput( t, u%rotors(iR), p%rotors(iR), p, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), y%rotors(iR), m%rotors(iR), ErrStat, ErrMsg, dYdu, dXdu, dXddu, dZdu)

END SUBROUTINE AD_JacobianPInput
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]

!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the inputs (u). The partial derivatives dY/du, dX/du, dXd/du, and dZ/du are returned.
SUBROUTINE Rot_JacobianPInput( t, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdu, dXdu, dXddu, dZdu)
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(RotInputType),                   INTENT(INOUT)           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(RotParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p_AD       !< Parameters
   TYPE(RotContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(RotDiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(RotConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(RotOtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(RotOutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdu.
   TYPE(RotMiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdu(:,:)  !< Partial derivatives of output functions (Y) with respect
                                                                               !!   to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdu(:,:)  !< Partial derivatives of continuous state functions (X) with
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddu(:,:) !< Partial derivatives of discrete state functions (Xd) with
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdu(:,:)  !< Partial derivatives of constraint state functions (Z) with
                                                                               !!   respect to the inputs (u) [intent in to avoid deallocation]
      ! local variables
   TYPE(RotOutputType)                                           :: y_p
   TYPE(RotOutputType)                                           :: y_m
   TYPE(RotContinuousStateType)                                  :: x_p
   TYPE(RotContinuousStateType)                                  :: x_m
   TYPE(RotContinuousStateType)                                  :: x_init
   TYPE(RotConstraintStateType)                                  :: z_copy
   TYPE(RotOtherStateType)                                       :: OtherState_copy
   TYPE(RotOtherStateType)                                       :: OtherState_init
   TYPE(RotInputType)                                            :: u_perturb
   REAL(R8Ki)                                                    :: delta_p, delta_m  ! delta change in input
   INTEGER(IntKi)                                                :: i
   
   integer, parameter                                            :: indx = 1      ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer(intKi)                                                :: ErrStat2
   character(ErrMsgLen)                                          :: ErrMsg2
   character(*), parameter                                       :: RoutineName = 'AD_JacobianPInput'


      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ''


      ! get OP values here (i.e., set inputs for BEMT):
   if ( p%FrozenWake ) then
      call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         
            ! compare m%BEMT_y arguments with call to BEMT_CalcOutput
      call computeFrozenWake(m%BEMT_u(indx), p%BEMT, m%BEMT_y, m%BEMT )
      m%BEMT%UseFrozenWake = .true.
   end if
   
   
   call AD_CopyRotContinuousStateType( x, x_init, MESH_NEWCOPY, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call AD_CopyRotOtherStateType( OtherState, OtherState_init, MESH_NEWCOPY, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      
      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
      
   ! initialize x_init so that we get accurrate values for first step
   if (.not. OtherState%BEMT%nodesInitialized ) then
      call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         
      call BEMT_InitStates(t, m%BEMT_u(indx), p%BEMT, x_init%BEMT, xd%BEMT, z%BEMT, OtherState_init%BEMT, m%BEMT, p_AD%AFI, ErrStat2, ErrMsg2 ) ! changes values only if states haven't been initialized
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   end if
   
   
      ! make a copy of the inputs to perturb
   call AD_CopyRotInputType( u, u_perturb, MESH_NEWCOPY, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
   

   IF ( PRESENT( dYdu ) ) THEN
      ! Calculate the partial derivative of the output functions (Y) with respect to the inputs (u) here:
      
      ! allocate dYdu
      if (.not. allocated(dYdu) ) then
         call AllocAry(dYdu,p%Jac_ny, size(p%Jac_u_indx,1),'dYdu', ErrStat2, ErrMsg2)
         call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      end if
   
      
         ! make a copy of outputs because we will need two for the central difference computations (with orientations)
      call AD_CopyRotOutputType( y, y_p, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      call AD_CopyRotOutputType( y, y_m, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         ! make a copy of the states to perturb
      call AD_CopyRotConstraintStateType( z, z_copy, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      call AD_CopyRotOtherStateType( OtherState_init, OtherState_copy, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
         
      do i=1,size(p%Jac_u_indx,1)
         
            ! get u_op + delta_p u
         call AD_CopyRotInputType( u, u_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_u( p, i, 1, u_perturb, delta_p )

         call AD_CopyRotConstraintStateType( z, z_copy, MESH_UPDATECOPY, ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         call AD_CopyRotOtherStateType( OtherState_init, OtherState_copy, MESH_UPDATECOPY, ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         
            ! get updated z%phi values:
         !call AD_UpdateStates( t, 1, (/u_perturb/), (/t/), p, x_copy, xd_copy, z_copy, OtherState_copy, m, errStat2, errMsg2 )
         !   call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         !bjj: this is what we want to do instead of the overkill of calling AD_UpdateStates
         call SetInputs(p, p_AD, u_perturb, m, indx, errStat2, errMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call UpdatePhi( m%BEMT_u(indx), p%BEMT, z_copy%BEMT%phi, p_AD%AFI, m%BEMT, OtherState_copy%BEMT%ValidPhi, errStat2, errMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later

            ! compute y at u_op + delta_p u
         call RotCalcOutput( t, u_perturb, p, p_AD, x_init, xd, z_copy, OtherState_copy, y_p, m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         
            
            ! get u_op - delta_m u
         call AD_CopyRotInputType( u, u_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_u( p, i, -1, u_perturb, delta_m )
         
         call AD_CopyRotConstraintStateType( z, z_copy, MESH_UPDATECOPY, ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         call AD_CopyRotOtherStateType( OtherState, OtherState_copy, MESH_UPDATECOPY, ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
            
            ! get updated z%phi values:
         !call RotUpdateStates( t, 1, (/u_perturb/), (/t/), p, x_copy, xd_copy, z_copy, OtherState_copy, m, errStat2, errMsg2 )
         !   call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         call SetInputs(p, p_AD, u_perturb, m, indx, errStat2, errMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call UpdatePhi( m%BEMT_u(indx), p%BEMT, z_copy%BEMT%phi, p_AD%AFI, m%BEMT, OtherState_copy%BEMT%ValidPhi, errStat2, errMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
            
            ! compute y at u_op - delta_m u
         call RotCalcOutput( t, u_perturb, p, p_AD, x_init, xd, z_copy, OtherState_copy, y_m, m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         
            
            ! get central difference:
         call Compute_dY( p, y_p, y_m, delta_p, delta_m, dYdu(:,i) )
         
      end do
      

      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
      
   END IF

   IF ( PRESENT( dXdu ) ) THEN

      ! Calculate the partial derivative of the continuous state functions (X) with respect to the inputs (u) here:

      ! allocate dXdu if necessary
      if (.not. allocated(dXdu)) then
         call AllocAry(dXdu, size(p%dx), size(p%Jac_u_indx,1), 'dXdu', ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      end if
      
         
      do i=1,size(p%Jac_u_indx,1)
         
            ! get u_op + delta u
         call AD_CopyRotInputType( u, u_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_u( p, i, 1, u_perturb, delta_p )

            ! compute x at u_op + delta u
         ! note that this routine updates z%phi instead of using the actual state value, so we don't need to call UpdateStates/UpdatePhi here to get z_op + delta_z:
         call RotCalcContStateDeriv( t, u_perturb, p, p_AD, x_init, xd, z, OtherState_init, m, x_p, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
            
                                         
            ! get u_op - delta u
         call AD_CopyRotInputType( u, u_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_u( p, i, -1, u_perturb, delta_m )
         
            ! compute x at u_op - delta u
         ! note that this routine updates z%phi instead of using the actual state value, so we don't need to call UpdateStates here to get z_op + delta_z:
         call RotCalcContStateDeriv( t, u_perturb, p, p_AD, x_init, xd, z, OtherState_init, m, x_m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) 
            
            
            ! get central difference:
            
            ! we may have had an error allocating memory, so we'll check
         if (ErrStat>=AbortErrLev) then 
            call cleanup()
            return
         end if         
         
            ! get central difference:
         call Compute_dX( p, x_p, x_m, delta_p, delta_m, dXdu(:,i) )

      end do

      call AD_DestroyRotContinuousStateType( x_p, ErrStat2, ErrMsg2 ) ! we don't need this any more
      call AD_DestroyRotContinuousStateType( x_m, ErrStat2, ErrMsg2 ) ! we don't need this any more
   END IF

   IF ( PRESENT( dXddu ) ) THEN
      if (allocated(dXddu)) deallocate(dXddu)
   END IF

   IF ( PRESENT( dZdu ) ) THEN
      if (allocated(dZdu)) deallocate(dZdu)
   END IF
   
   call cleanup()
contains
   subroutine cleanup()
      m%BEMT%UseFrozenWake = .false.
   
      call AD_DestroyRotOutputType(                y_p,  ErrStat2, ErrMsg2)
      call AD_DestroyRotOutputType(                y_m,  ErrStat2, ErrMsg2)
      call AD_DestroyRotContinuousStateType(        x_p,  ErrStat2, ErrMsg2)
      call AD_DestroyRotContinuousStateType(        x_m,  ErrStat2, ErrMsg2)
      call AD_DestroyRotContinuousStateType(     x_init,  ErrStat2, ErrMsg2)
      call AD_DestroyRotConstraintStateType(         z_copy, ErrStat2, ErrMsg2)
      call AD_DestroyRotOtherStateType( OtherState_copy, ErrStat2, ErrMsg2)
      call AD_DestroyRotOtherStateType( OtherState_init, ErrStat2, ErrMsg2)
                        
      call AD_DestroyRotInputType( u_perturb, ErrStat2, ErrMsg2 )
   end subroutine cleanup

END SUBROUTINE Rot_JacobianPInput

!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the continuous states (x). The partial derivatives dY/dx, dX/dx, dXd/dx, and dZ/dx are returned.
SUBROUTINE AD_JacobianPContState( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdx, dXdx, dXddx, dZdx )
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(AD_InputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(AD_DiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(AD_ConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(AD_OtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(AD_OutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdx.
   TYPE(AD_MiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdx(:,:)  !< Partial derivatives of output functions
                                                                               !!   (Y) with respect to the continuous
                                                                               !!   states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdx(:,:)  !< Partial derivatives of continuous state
                                                                               !!   functions (X) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddx(:,:) !< Partial derivatives of discrete state
                                                                               !!   functions (Xd) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdx(:,:)  !< Partial derivatives of constraint state
                                                                               !!   functions (Z) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]
   !
   integer(IntKi), parameter :: iR =1 ! Rotor index

   if (size(p%rotors)>1) then
      errStat = ErrID_Fatal
      errMsg = 'Linearization with more than one rotor not supported'
      return
   endif

   call RotJacobianPContState( t, u%rotors(iR), p%rotors(iR), p, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), y%rotors(iR), m%rotors(iR), ErrStat, ErrMsg, dYdx, dXdx, dXddx, dZdx )


END SUBROUTINE AD_JacobianPContState

!----------------------------------------------------------------------------------------------------------------------------------
!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the continuous states (x). The partial derivatives dY/dx, dX/dx, dXd/dx, and dZ/dx are returned.
SUBROUTINE RotJacobianPContState( t, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdx, dXdx, dXddx, dZdx )
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(RotInputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(RotParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p_AD       !< Parameters
   TYPE(RotContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(RotDiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(RotConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(RotOtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(RotOutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdx.
   TYPE(RotMiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdx(:,:)  !< Partial derivatives of output functions
                                                                               !!   (Y) with respect to the continuous
                                                                               !!   states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdx(:,:)  !< Partial derivatives of continuous state
                                                                               !!   functions (X) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddx(:,:) !< Partial derivatives of discrete state
                                                                               !!   functions (Xd) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdx(:,:)  !< Partial derivatives of constraint state
                                                                               !!   functions (Z) with respect to
                                                                               !!   the continuous states (x) [intent in to avoid deallocation]

   ! local variables
   TYPE(RotOutputType)                                           :: y_p
   TYPE(RotOutputType)                                           :: y_m
   TYPE(RotContinuousStateType)                                  :: x_p
   TYPE(RotContinuousStateType)                                  :: x_m
   TYPE(RotContinuousStateType)                                  :: x_perturb
   TYPE(RotContinuousStateType)                                  :: x_init
   TYPE(RotOtherStateType)                                       :: OtherState_init
   REAL(R8Ki)                                                    :: delta_p, delta_m  ! delta change in state
   INTEGER(IntKi)                                                :: i
   
   integer, parameter                                            :: indx = 1      ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer(intKi)                                                :: ErrStat2
   character(ErrMsgLen)                                          :: ErrMsg2
   character(*), parameter                                       :: RoutineName = 'AD_JacobianPContState'
   

      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ''


   if ( p%FrozenWake ) then
      call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         
         ! compare arguments with call to BEMT_CalcOutput
      call computeFrozenWake(m%BEMT_u(indx), p%BEMT, m%BEMT_y, m%BEMT )
      m%BEMT%UseFrozenWake = .true.
   end if


   call AD_CopyRotContinuousStateType( x, x_perturb, MESH_NEWCOPY, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      
   call AD_CopyRotContinuousStateType( x, x_init, MESH_NEWCOPY, ErrStat2, ErrMsg2 )
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call AD_CopyRotOtherStateType( OtherState, OtherState_init, MESH_NEWCOPY, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      
      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
      
   ! initialize x_init so that we get accurrate values for 
   if (.not. OtherState%BEMT%nodesInitialized ) then
      call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         
      call BEMT_InitStates(t, m%BEMT_u(indx), p%BEMT, x_init%BEMT, xd%BEMT, z%BEMT, OtherState_init%BEMT, m%BEMT, p_AD%AFI, ErrStat2, ErrMsg2 ) ! changes values only if states haven't been initialized
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   end if
   
   
   IF ( PRESENT( dYdx ) ) THEN

      ! Calculate the partial derivative of the output functions (Y) with respect to the continuous states (x) here:

      ! allocate dYdx if necessary
      if (.not. allocated(dYdx)) then
         call AllocAry(dYdx, p%Jac_ny, size(p%dx), 'dYdx', ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      end if
      
         ! make a copy of outputs because we will need two for the central difference computations (with orientations)
      call AD_CopyRotOutputType( y, y_p, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      call AD_CopyRotOutputType( y, y_m, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if

      do i=1,size(p%dx)
         
            ! get x_op + delta_p x
         call AD_CopyRotContinuousStateType( x_init, x_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
         call Perturb_x( p, i, 1, x_perturb, delta_p )


            ! compute y at x_op + delta_p x
         ! NOTE: z_op is the same as z because x_perturb does not affect the values of phi, thus I am not updating the states or calling UpdatePhi to get z_perturb.
         call RotCalcOutput( t, u, p, p_AD, x_perturb, xd, z, OtherState_init, y_p, m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
         
            
            ! get x_op - delta_m x
         call AD_CopyRotContinuousStateType( x_init, x_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_x( p, i, -1, x_perturb, delta_m )
         
            ! compute y at x_op - delta_m x
         ! NOTE: z_op is the same as z because x_perturb does not affect the values of phi, thus I am not updating the states or calling UpdatePhi to get z_perturb.
         call RotCalcOutput( t, u, p, p_AD, x_perturb, xd, z, OtherState_init, y_m, m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
         
            
            ! get central difference:            
         call Compute_dY( p, y_p, y_m, delta_p, delta_m, dYdx(:,i) )
         
      end do
      

      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
      call AD_DestroyRotOutputType( y_p, ErrStat2, ErrMsg2 ) ! we don't need this any more   
      call AD_DestroyRotOutputType( y_m, ErrStat2, ErrMsg2 ) ! we don't need this any more         

   END IF

   IF ( PRESENT( dXdx ) ) THEN

      ! Calculate the partial derivative of the continuous state functions (X) with respect to the continuous states (x) here:

      ! allocate and set dXdx

      ! Calculate the partial derivative of the continuous state functions (X) with respect to the inputs (u) here:

      ! allocate dXdx if necessary
      if (.not. allocated(dXdx)) then
         call AllocAry(dXdx, size(p%dx), size(p%dx), 'dXdx', ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      end if
      
         
      do i=1,size(p%dx,1)
         
            ! get x_op + delta x
         call AD_CopyRotContinuousStateType( x_init, x_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_x( p, i, 1, x_perturb, delta_p )

            ! compute X at x_op + delta x
         ! NOTE: z_op is the same as z because x_perturb does not affect the values of phi, thus I am not updating the states or calling UpdatePhi to get z_perturb.
         call RotCalcContStateDeriv( t, u, p, p_AD, x_perturb, xd, z, OtherState_init, m, x_p, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
            
                                         
            ! get x_op - delta x
         call AD_CopyRotContinuousStateType( x_init, x_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later
         call Perturb_x( p, i, -1, x_perturb, delta_m )
         
            ! compute x at u_op - delta u
         ! NOTE: z_op is the same as z because x_perturb does not affect the values of phi, thus I am not updating the states or calling UpdatePhi to get z_perturb.
         call RotCalcContStateDeriv( t, u, p, p_AD, x_perturb, xd, z, OtherState_init, m, x_m, ErrStat2, ErrMsg2 ) 
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) 
            
            
            ! get central difference:
            
            ! we may have had an error allocating memory, so we'll check
         if (ErrStat>=AbortErrLev) then 
            call cleanup()
            return
         end if         
         
            ! get central difference:
         call Compute_dX( p, x_p, x_m, delta_p, delta_m, dXdx(:,i) )

      end do

      call AD_DestroyRotContinuousStateType( x_p, ErrStat2, ErrMsg2 ) ! we don't need this any more
      call AD_DestroyRotContinuousStateType( x_m, ErrStat2, ErrMsg2 ) ! we don't need this any more
   
   
   END IF

   IF ( PRESENT( dXddx ) ) THEN

      ! Calculate the partial derivative of the discrete state functions (Xd) with respect to the continuous states (x) here:

      ! allocate and set dXddx

   END IF

   IF ( PRESENT( dZdx ) ) THEN


      ! Calculate the partial derivative of the constraint state functions (Z) with respect to the continuous states (x) here:

      ! allocate and set dZdx

   END IF

   call cleanup()
contains
   subroutine cleanup()
      m%BEMT%UseFrozenWake = .false.
   
      call AD_DestroyRotOutputType(    y_p,       ErrStat2, ErrMsg2)
      call AD_DestroyRotOutputType(    y_m,       ErrStat2, ErrMsg2)
      call AD_DestroyRotContinuousStateType( x_p,       ErrStat2, ErrMsg2)
      call AD_DestroyRotContinuousStateType( x_m,       ErrStat2, ErrMsg2)
      
      call AD_DestroyRotContinuousStateType( x_perturb, ErrStat2, ErrMsg2 )
      call AD_DestroyRotContinuousStateType( x_init,    ErrStat2, ErrMsg2 )
      call AD_DestroyRotOtherStateType( OtherState_init, ErrStat2, ErrMsg2 )
   end subroutine cleanup

END SUBROUTINE RotJacobianPContState
!----------------------------------------------------------------------------------------------------------------------------------
!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the discrete states (xd). The partial derivatives dY/dxd, dX/dxd, dXd/dxd, and dZ/dxd are returned.
SUBROUTINE AD_JacobianPDiscState( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdxd, dXdxd, dXddxd, dZdxd )
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(AD_InputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(AD_DiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(AD_ConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(AD_OtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(AD_OutputType),                  INTENT(IN   )           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdxd.
   TYPE(AD_MiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdxd(:,:) !< Partial derivatives of output functions
                                                                               !!  (Y) with respect to the discrete
                                                                               !!  states (xd) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdxd(:,:) !< Partial derivatives of continuous state
                                                                               !!   functions (X) with respect to the
                                                                               !!   discrete states (xd) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddxd(:,:)!< Partial derivatives of discrete state
                                                                               !!   functions (Xd) with respect to the
                                                                               !!   discrete states (xd) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdxd(:,:) !< Partial derivatives of constraint state
                                                                               !!   functions (Z) with respect to the
                                                                               !!   discrete states (xd) [intent in to avoid deallocation]


      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ''


   IF ( PRESENT( dYdxd ) ) THEN

      ! Calculate the partial derivative of the output functions (Y) with respect to the discrete states (xd) here:

      ! allocate and set dYdxd

   END IF

   IF ( PRESENT( dXdxd ) ) THEN

      ! Calculate the partial derivative of the continuous state functions (X) with respect to the discrete states (xd) here:

      ! allocate and set dXdxd

   END IF

   IF ( PRESENT( dXddxd ) ) THEN

      ! Calculate the partial derivative of the discrete state functions (Xd) with respect to the discrete states (xd) here:

      ! allocate and set dXddxd

   END IF

   IF ( PRESENT( dZdxd ) ) THEN

      ! Calculate the partial derivative of the constraint state functions (Z) with respect to the discrete states (xd) here:

      ! allocate and set dZdxd

   END IF


END SUBROUTINE AD_JacobianPDiscState
!----------------------------------------------------------------------------------------------------------------------------------
!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the constraint states (z). The partial derivatives dY/dz, dX/dz, dXd/dz, and dZ/dz are returned.
SUBROUTINE AD_JacobianPConstrState( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdz, dXdz, dXddz, dZdz )
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(AD_InputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(AD_DiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(AD_ConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(AD_OtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(AD_OutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdz.
   TYPE(AD_MiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdz(:,:)  !< Partial derivatives of output
                                                                               !!  functions (Y) with respect to the
                                                                               !!  constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdz(:,:)  !< Partial derivatives of continuous
                                                                               !!  state functions (X) with respect to
                                                                               !!  the constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddz(:,:) !< Partial derivatives of discrete state
                                                                               !!  functions (Xd) with respect to the
                                                                               !!  constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdz(:,:)  !< Partial derivatives of constraint
                                                                               !! state functions (Z) with respect to
                                                                               !!  the constraint states (z) [intent in to avoid deallocation]
   !
   integer(IntKi), parameter :: iR =1 ! Rotor index

   if (size(p%rotors)>1) then
      errStat = ErrID_Fatal
      errMsg = 'Linearization with more than one rotor not supported'
      return
   endif

   call RotJacobianPConstrState( t, u%rotors(iR), p%rotors(iR), p, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), y%rotors(iR), m%rotors(iR), errStat, errMsg, dYdz, dXdz, dXddz, dZdz )

END SUBROUTINE AD_JacobianPConstrState
!----------------------------------------------------------------------------------------------------------------------------------
!> Routine to compute the Jacobians of the output (Y), continuous- (X), discrete- (Xd), and constraint-state (Z) functions
!! with respect to the constraint states (z). The partial derivatives dY/dz, dX/dz, dXd/dz, and dZ/dz are returned.
SUBROUTINE RotJacobianPConstrState( t, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, dYdz, dXdz, dXddz, dZdz )
!..................................................................................................................................

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(RotInputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(RotParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p_AD       !< Parameters
   TYPE(RotContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(RotDiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(RotConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(RotOtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(RotOutputType),                  INTENT(INOUT)           :: y          !< Output (change to inout if a mesh copy is required);
                                                                               !!   Output fields are not used by this routine, but type is
                                                                               !!   available here so that mesh parameter information (i.e.,
                                                                               !!   connectivity) does not have to be recalculated for dYdz.
   TYPE(RotMiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dYdz(:,:)  !< Partial derivatives of output
                                                                               !!  functions (Y) with respect to the
                                                                               !!  constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXdz(:,:)  !< Partial derivatives of continuous
                                                                               !!  state functions (X) with respect to
                                                                               !!  the constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dXddz(:,:) !< Partial derivatives of discrete state
                                                                               !!  functions (Xd) with respect to the
                                                                               !!  constraint states (z) [intent in to avoid deallocation]
   REAL(R8Ki), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dZdz(:,:)  !< Partial derivatives of constraint
                                                                               !! state functions (Z) with respect to
                                                                               !!  the constraint states (z) [intent in to avoid deallocation]

      ! local variables
   TYPE(RotOutputType)                                           :: y_p
   TYPE(RotOutputType)                                           :: y_m
   TYPE(RotConstraintStateType)                                  :: Z_p
   TYPE(RotConstraintStateType)                                  :: Z_m
   TYPE(RotConstraintStateType)                                  :: z_perturb
   REAL(R8Ki)                                                    :: delta_p, delta_m  ! delta change in state
   INTEGER(IntKi)                                                :: i, j, k, n, k2, j2   

   integer, parameter                                            :: indx = 1      ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt
   integer, parameter                                            :: op_indx = 2   ! m%BEMT_u(1) is at t; m%BEMT_u(2) is t+dt or the input at OP
   integer(intKi)                                                :: ErrStat2
   character(ErrMsgLen)                                          :: ErrMsg2
   character(*), parameter                                       :: RoutineName = 'AD_JacobianPConstrState'

   
      ! local variables
      
   
      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ''

      ! get OP values here:   
   !call AD_CalcOutput( t, u, p, x, xd, z, OtherState, y, m, ErrStat2, ErrMsg2 )  ! (bjj: is this necessary? if not, still need to get BEMT inputs)
   call SetInputs(p, p_AD, u, m, indx, errStat2, errMsg2)  
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
   call BEMT_CopyInput( m%BEMT_u(indx), m%BEMT_u(op_indx), MESH_UPDATECOPY, ErrStat2, ErrMsg2) ! copy the BEMT OP inputs to a temporary location that won't be overwritten
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later                        
 
      
   if ( p%FrozenWake ) then            
            ! compare arguments with call to BEMT_CalcOutput   
      call computeFrozenWake(m%BEMT_u(op_indx), p%BEMT, m%BEMT_y, m%BEMT )      
      m%BEMT%UseFrozenWake = .true.
   end if
   
   
      ! make a copy of the constraint states to perturb
   call AD_CopyRotConstraintStateType( z, z_perturb, MESH_NEWCOPY, ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
   
   
   IF ( PRESENT( dYdz ) ) THEN

         ! Calculate the partial derivative of the output functions (Y) with respect to the constraint states (z) here:

      ! allocate and set dYdz
      if (.not. allocated(dYdz) ) then
         call AllocAry(dYdz,p%Jac_ny, size(z%BEMT%phi),'dYdz', ErrStat2, ErrMsg2)
         call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      end if

      
         ! make a copy of outputs because we will need two for the central difference computations (with orientations)
      call AD_CopyRotOutputType( y, y_p, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      call AD_CopyRotOutputType( y, y_m, MESH_NEWCOPY, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if
      
         
      do k=1,p%NumBlades ! size(z%BEMT%Phi,2)
         do j=1,p%NumBlNds ! size(z%BEMT%Phi,1)                  
            i = (k-1)*p%NumBlNds + j
            
               ! need a check if F = 0 for this case:
   
            if ( p%BEMT%FixedInductions(j,k) ) then
               ! F is zero, we we need to skip this perturbation
               dYdz(:,i) = 0.0_ReKi
            else                        
            
               call Get_phi_perturbations(p%BEMT, m%BEMT, z%BEMT%phi(j,k), delta_p, delta_m)
               
                  ! get z_op + delta_p z
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k) + delta_p
            
                  ! compute y at z_op + delta_p z
               call RotCalcOutput( t, u, p, p_AD, x, xd, z_perturb, OtherState, y_p, m, ErrStat2, ErrMsg2 ) 
                  call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
            
            
                  ! get z_op - delta_m z
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k) - delta_m
            
                  ! compute y at z_op - delta_m z
               call RotCalcOutput( t, u, p, p_AD, x, xd, z_perturb, OtherState, y_m, m, ErrStat2, ErrMsg2 ) 
                  call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) ! we shouldn't have any errors about allocating memory here so I'm not going to return-on-error until later            
            

                  ! get central difference:            
               call Compute_dY( p, y_p, y_m, delta_p, delta_m, dYdz(:,i) )
               
               
                  ! put z_perturb back (for next iteration):
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k)
            end if
         
         end do
      end do
      
      if (ErrStat>=AbortErrLev) then
         call cleanup()
         return
      end if
      call AD_DestroyRotOutputType( y_p, ErrStat2, ErrMsg2 ) ! we don't need this any more   
      call AD_DestroyRotOutputType( y_m, ErrStat2, ErrMsg2 ) ! we don't need this any more   
      
      
   END IF

   IF ( PRESENT( dXdz ) ) THEN
      if (allocated(dXdz)) deallocate(dXdz)
   END IF

   IF ( PRESENT( dXddz ) ) THEN
      if (allocated(dXddz)) deallocate(dXddz)
   END IF

   IF ( PRESENT(dZdz) ) THEN

      call CheckLinearizationInput(p%BEMT, m%BEMT_u(op_indx), z%BEMT, m%BEMT, OtherState%BEMT, ErrStat2, ErrMsg2)      
         call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if         
         
         ! Calculate the partial derivative of the constraint state functions (Z) with respect to the constraint states (z) here:

      ! allocate and set dZdz
      if (.not. allocated(dZdz)) then
         call AllocAry(dZdz,size(z%BEMT%phi), size(z%BEMT%phi),'dZdz', ErrStat2, ErrMsg2)
         call setErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call cleanup()
            return
         end if         
      end if
      
      
      call AD_CopyRotConstraintStateType( z, z_perturb, MESH_UPDATECOPY, ErrStat2, ErrMsg2 )
      
      do k=1,p%NumBlades ! size(z%BEMT%Phi,2)
         do j=1,p%NumBlNds ! size(z%BEMT%Phi,1)                  
            i = (k-1)*p%NumBlNds + j
               
            if ( p%BEMT%FixedInductions(j,k) ) then
               ! F is zero, we we need to skip this perturbation
               dZdz(:,i) = 0.0_ReKi
               dZdz(i,i) = 1.0_ReKi                              
            else                        
            
               call Get_phi_perturbations(p%BEMT, m%BEMT, z%BEMT%phi(j,k), delta_p, delta_m)
            
                  ! get z_op + delta_p z
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k) + delta_p

                  ! compute z_p at z_op + delta_p z
               call RotCalcConstrStateResidual( t, u, p, p_AD, x, xd, z_perturb, OtherState, m, z_p, ErrStat2, ErrMsg2 ) 
                  call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
            
                                         
                  ! get z_op - delta_m z
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k) - delta_m
                     
                  ! compute z_m at u_op - delta_m u
               call RotCalcConstrStateResidual( t, u, p, p_AD, x, xd, z_perturb, OtherState, m, z_m, ErrStat2, ErrMsg2 ) 
                  call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName) 
                  if (ErrStat>=AbortErrLev) then 
                     call cleanup()
                     return
                  end if         
            
                  ! get central difference:            
                     
               do k2=1,p%NumBlades ! size(z%BEMT%Phi,2)
                  do j2=1,p%NumBlNds ! size(z%BEMT%Phi,1)
                     n = (k2-1)*p%NumBlNds + j2
                     dZdz(n,i) = z_p%BEMT%Phi(j2,k2) - z_m%BEMT%Phi(j2,k2)
                  end do            
               end do
         
               dZdz(:,i) = dZdz(:,i) / (delta_p + delta_m) 
         
                  ! put z_perturb back (for next iteration):
               z_perturb%BEMT%phi(j,k) = z%BEMT%phi(j,k)
               
            end if
            
         end do         
      end do
      
      call AD_DestroyRotConstraintStateType( z_p, ErrStat2, ErrMsg2 ) ! we don't need this any more
      call AD_DestroyRotConstraintStateType( z_m, ErrStat2, ErrMsg2 ) ! we don't need this any more      
      
   END IF
     
   call cleanup()
   
contains
   subroutine cleanup()
      m%BEMT%UseFrozenWake = .false.

      call AD_DestroyRotOutputType(            y_p, ErrStat2, ErrMsg2 )
      call AD_DestroyRotOutputType(            y_m, ErrStat2, ErrMsg2 )
      call AD_DestroyRotConstraintStateType(       z_p, ErrStat2, ErrMsg2 )
      call AD_DestroyRotConstraintStateType(       z_m, ErrStat2, ErrMsg2 )
      call AD_DestroyRotConstraintStateType( z_perturb, ErrStat2, ErrMsg2 )
   end subroutine cleanup   

END SUBROUTINE RotJacobianPConstrState
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
!> Routine to pack the data structures representing the operating points into arrays for linearization.
SUBROUTINE AD_GetOP( t, u, p, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, u_op, y_op, x_op, dx_op, xd_op, z_op )

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(AD_InputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(AD_DiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(AD_ConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(AD_OtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(AD_OutputType),                  INTENT(IN   )           :: y          !< Output at operating point
   TYPE(AD_MiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: u_op(:)    !< values of linearized inputs
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: y_op(:)    !< values of linearized outputs
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: x_op(:)    !< values of linearized continuous states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dx_op(:)   !< values of first time derivatives of linearized continuous states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: xd_op(:)   !< values of linearized discrete states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: z_op(:)    !< values of linearized constraint states
   !
   integer(IntKi), parameter :: iR =1 ! Rotor index

   if (size(p%rotors)>1) then
      errStat = ErrID_Fatal
      errMsg = 'Linearization with more than one rotor not supported'
      return
   endif

   call RotGetOP( t, u%rotors(iR), p%rotors(iR), p, x%rotors(iR), xd%rotors(iR), z%rotors(iR), OtherState%rotors(iR), y%rotors(iR), m%rotors(iR), errStat, errMsg, u_op, y_op, x_op, dx_op, xd_op, z_op )

END SUBROUTINE AD_GetOP

!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
!> Routine to pack the data structures representing the operating points into arrays for linearization.
SUBROUTINE RotGetOP( t, u, p, p_AD, x, xd, z, OtherState, y, m, ErrStat, ErrMsg, u_op, y_op, x_op, dx_op, xd_op, z_op )

   REAL(DbKi),                           INTENT(IN   )           :: t          !< Time in seconds at operating point
   TYPE(RotInputType),                   INTENT(IN   )           :: u          !< Inputs at operating point (may change to inout if a mesh copy is required)
   TYPE(RotParameterType),               INTENT(IN   )           :: p          !< Parameters
   TYPE(AD_ParameterType),               INTENT(IN   )           :: p_AD       !< Parameters
   TYPE(RotContinuousStateType),         INTENT(IN   )           :: x          !< Continuous states at operating point
   TYPE(RotDiscreteStateType),           INTENT(IN   )           :: xd         !< Discrete states at operating point
   TYPE(RotConstraintStateType),         INTENT(IN   )           :: z          !< Constraint states at operating point
   TYPE(RotOtherStateType),              INTENT(IN   )           :: OtherState !< Other states at operating point
   TYPE(RotOutputType),                  INTENT(IN   )           :: y          !< Output at operating point
   TYPE(RotMiscVarType),                 INTENT(INOUT)           :: m          !< Misc/optimization variables
   INTEGER(IntKi),                       INTENT(  OUT)           :: ErrStat    !< Error status of the operation
   CHARACTER(*),                         INTENT(  OUT)           :: ErrMsg     !< Error message if ErrStat /= ErrID_None
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: u_op(:)    !< values of linearized inputs
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: y_op(:)    !< values of linearized outputs
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: x_op(:)    !< values of linearized continuous states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: dx_op(:)   !< values of first time derivatives of linearized continuous states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: xd_op(:)   !< values of linearized discrete states
   REAL(ReKi), ALLOCATABLE, OPTIONAL,    INTENT(INOUT)           :: z_op(:)    !< values of linearized constraint states

   INTEGER(IntKi)                                                :: index, i, j, k
   INTEGER(IntKi)                                                :: nu
   INTEGER(IntKi)                                                :: ErrStat2
   CHARACTER(ErrMsgLen)                                          :: ErrMsg2
   CHARACTER(*), PARAMETER                                       :: RoutineName = 'AD_GetOP'
   LOGICAL                                                       :: FieldMask(FIELDMASK_SIZE)
   TYPE(RotContinuousStateType)                                  :: dxdt

   
      ! Initialize ErrStat

   ErrStat = ErrID_None
   ErrMsg  = ''

   IF ( PRESENT( u_op ) ) THEN
      
      nu = size(p%Jac_u_indx,1) + u%TowerMotion%NNodes * 6 & ! Jac_u_indx has 3 orientation angles, but the OP needs the full 9 elements of the DCM
                                + u%hubMotion%NNodes * 6     ! Jac_u_indx has 3 orientation angles, but the OP needs the full 9 elements of the DCM
      do i=1,p%NumBlades
         nu = nu + u%BladeMotion(i)%NNodes * 6 & ! Jac_u_indx has 3 orientation angles, but the OP needs the full 9 elements of the DCM
             + u%BladeRootMotion(i)%NNodes * 6   ! Jac_u_indx has 3 orientation angles, but the OP needs the full 9 elements of the DCM
      end do      
                  
      if (.not. allocated(u_op)) then
         call AllocAry(u_op, nu, 'u_op', ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
            if (ErrStat >= AbortErrLev) return
      end if
      

      index = 1
      FieldMask = .false.
      FieldMask(MASKID_TRANSLATIONDISP) = .true.
      FieldMask(MASKID_Orientation) = .true.
      FieldMask(MASKID_TRANSLATIONVel) = .true.
      call PackMotionMesh(u%TowerMotion, u_op, index, FieldMask=FieldMask)
   
      FieldMask(MASKID_TRANSLATIONVel) = .false.
      FieldMask(MASKID_RotationVel) = .true.
      call PackMotionMesh(u%HubMotion, u_op, index, FieldMask=FieldMask)
   
      FieldMask = .false.
      FieldMask(MASKID_Orientation) = .true.
      do k = 1,p%NumBlades
         call PackMotionMesh(u%BladeRootMotion(k), u_op, index, FieldMask=FieldMask)
      end do
   
      FieldMask(MASKID_TRANSLATIONDISP) = .true.
      FieldMask(MASKID_Orientation) = .true.
      FieldMask(MASKID_TRANSLATIONVel)  = .true.
      FieldMask(MASKID_RotationVel) = .true.
      FieldMask(MASKID_TRANSLATIONAcc) = .true.
      do k=1,p%NumBlades     
         call PackMotionMesh(u%BladeMotion(k), u_op, index, FieldMask=FieldMask)
      end do
   
      do k=1,p%NumBlades
         do i=1,p%NumBlNds
            do j=1,3
               u_op(index) = u%InflowOnBlade(j,i,k)
               index = index + 1
            end do            
         end do
      end do

      do i=1,p%NumTwrNds
         do j=1,3
            u_op(index) = u%InflowOnTower(j,i)
            index = index + 1
         end do            
      end do

      do k=1,p%NumBlades
         do j = 1, size(u%UserProp,1) ! Number of nodes for a blade
            u_op(index) = u%UserProp(j,k)
            index = index + 1
         end do
      end do
      
                  ! I'm not including this in the linearization yet
         !do i=1,u%NacelleMotion%NNodes ! 1 or 0
         !   do j=1,3
         !      u_op(index) = u%InflowOnNacelle(j)
         !      index = index + 1
         !   end do
         !end do
         !
         !do i=1,u%HubMotion%NNodes ! 1
         !   do j=1,3
         !      u_op(index) = u%InflowOnHub(j)
         !      index = index + 1
         !   end do
         !end do
         
   END IF

   IF ( PRESENT( y_op ) ) THEN
      
      if (.not. allocated(y_op)) then
         call AllocAry(y_op, p%Jac_ny, 'y_op', ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
            if (ErrStat >= AbortErrLev) return
      end if
      
      

      index = 1
      call PackLoadMesh(y%TowerLoad, y_op, index)
      do k=1,p%NumBlades
         call PackLoadMesh(y%BladeLoad(k), y_op, index)                  
      end do
   
      index = index - 1
      do i=1,p%NumOuts + p%BldNd_TotNumOuts
         y_op(i+index) = y%WriteOutput(i)
      end do   
         
      
   END IF

   IF ( PRESENT( x_op ) ) THEN
   
      if (.not. allocated(x_op)) then
         call AllocAry(x_op, p%BEMT%DBEMT%lin_nx + p%BEMT%UA%lin_nx,'x_op',ErrStat2,ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) return
      end if

      index = 1
         ! set linearization operating points:
      if (p%BEMT%DBEMT%lin_nx>0) then
         do j=1,p%NumBlades ! size(x%BEMT%DBEMT%element,2)
            do i=1,p%NumBlNds ! size(x%BEMT%DBEMT%element,1)
               do k=1,size(x%BEMT%DBEMT%element(i,j)%vind)
                  x_op(index) = x%BEMT%DBEMT%element(i,j)%vind(k)
                  index = index + 1
               end do
            end do
         end do
   
         do j=1,p%NumBlades ! size(x%BEMT%DBEMT%element,2)
            do i=1,p%NumBlNds ! size(x%BEMT%DBEMT%element,1)
               do k=1,size(x%BEMT%DBEMT%element(i,j)%vind_dot)
                  x_op(index) = x%BEMT%DBEMT%element(i,j)%vind_dot(k)
                  index = index + 1
               end do
            end do
         end do
      
      end if
   
      if (p%BEMT%UA%lin_nx>0) then
         do j=1,p%NumBlades ! size(x%BEMT%UA%element,2)
            do i=1,p%NumBlNds ! size(x%BEMT%UA%element,1)
               do k=1,4 !size(x%BEMT%UA%element(i,j)%x) !linearize only first 4 states (5th is vortex)
                  x_op(index) = x%BEMT%UA%element(i,j)%x(k)
                  index = index + 1
               end do
            end do
         end do
      
      end if
      
   END IF

   IF ( PRESENT( dx_op ) ) THEN
   
      if (.not. allocated(dx_op)) then
         call AllocAry(dx_op, p%BEMT%DBEMT%lin_nx + p%BEMT%UA%lin_nx,'dx_op',ErrStat2,ErrMsg2)
            call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
            if (ErrStat>=AbortErrLev) return
      end if

      call RotCalcContStateDeriv(t, u, p, p_AD, x, xd, z, OtherState, m, dxdt, ErrStat2, ErrMsg2)
         call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
         if (ErrStat>=AbortErrLev) then
            call AD_DestroyRotContinuousStateType( dxdt, ErrStat2, ErrMsg2)
            return
         end if
      
      index = 1
         ! set linearization operating points:
      if (p%BEMT%DBEMT%lin_nx>0) then

         do j=1,p%NumBlades ! size(dxdt%BEMT%DBEMT%element,2)
            do i=1,p%NumBlNds ! size(dxdt%BEMT%DBEMT%element,1)
               do k=1,size(dxdt%BEMT%DBEMT%element(i,j)%vind)
                  dx_op(index) = dxdt%BEMT%DBEMT%element(i,j)%vind(k)
                  index = index + 1
               end do
            end do
         end do
   
         do j=1,p%NumBlades ! size(dxdt%BEMT%DBEMT%element,2)
            do i=1,p%NumBlNds ! size(dxdt%BEMT%DBEMT%element,1)
               do k=1,size(dxdt%BEMT%DBEMT%element(i,j)%vind_dot)
                  dx_op(index) = dxdt%BEMT%DBEMT%element(i,j)%vind_dot(k)
                  index = index + 1
               end do
            end do
         end do
      
      end if
   
      if (p%BEMT%UA%lin_nx>0) then
         do j=1,p%NumBlades ! size(dxdt%BEMT%UA%element,2)
            do i=1,p%NumBlNds ! size(dxdt%BEMT%UA%element,1)
               do k=1,4 !size(dxdt%BEMT%UA%element(i,j)%x) don't linearize 5th state
                  dx_op(index) = dxdt%BEMT%UA%element(i,j)%x(k)
                  index = index + 1
               end do
            end do
         end do
      end if
      
      call AD_DestroyRotContinuousStateType( dxdt, ErrStat2, ErrMsg2)
      
   END IF

   IF ( PRESENT( xd_op ) ) THEN

   END IF
   
   IF ( PRESENT( z_op ) ) THEN

      if (.not. allocated(z_op)) then
         call AllocAry(z_op, p%NumBlades*p%NumBlNds, 'z_op', ErrStat2, ErrMsg2)
            call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
            if (ErrStat >= AbortErrLev) return
      end if
      
   
      index = 1
      do k=1,p%NumBlades ! size(z%BEMT%Phi,2)
         do i=1,p%NumBlNds ! size(z%BEMT%Phi,1)
            z_op(index) = z%BEMT%phi(i,k)
            index = index + 1
         end do
      end do
      
   END IF

END SUBROUTINE RotGetOP
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++   
SUBROUTINE Init_Jacobian_y( p, y, InitOut, ErrStat, ErrMsg)

   TYPE(RotParameterType)            , INTENT(INOUT) :: p                     !< parameters
   TYPE(RotOutputType)               , INTENT(IN   ) :: y                     !< outputs
   TYPE(RotInitOutputType)           , INTENT(INOUT) :: InitOut               !< Initialization output data (for Jacobian row/column names)
   
   INTEGER(IntKi)                    , INTENT(  OUT) :: ErrStat               !< Error status of the operation
   CHARACTER(*)                      , INTENT(  OUT) :: ErrMsg                !< Error message if ErrStat /= ErrID_None
   
      ! local variables:
   INTEGER(IntKi)                :: i, j, k, indx_next, indx_last
   INTEGER(IntKi)                                    :: ErrStat2
   CHARACTER(ErrMsgLen)                              :: ErrMsg2
   CHARACTER(*), PARAMETER                           :: RoutineName = 'Init_Jacobian_y'
   logical, allocatable                              :: AllOut(:)
                        
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   
      ! determine how many outputs there are in the Jacobians     
   p%Jac_ny = y%TowerLoad%NNodes * 6         & ! 3 forces + 3 moments at each node
            + p%NumOuts + p%BldNd_TotNumOuts   ! WriteOutput values 
      
   do k=1,p%NumBlades
      p%Jac_ny = p%Jac_ny + y%BladeLoad(k)%NNodes * 6  ! 3 forces + 3 moments at each node
   end do   
   
   
      ! get the names of the linearized outputs:
   call AllocAry(InitOut%LinNames_y, p%Jac_ny,'LinNames_y',ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   call AllocAry(InitOut%RotFrame_y, p%Jac_ny,'RotFrame_y',ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      if (ErrStat >= AbortErrLev) return
   
         
   InitOut%RotFrame_y = .false. ! default all to false, then set the true ones below
   indx_next = 1  
   call PackLoadMesh_Names(y%TowerLoad, 'Tower', InitOut%LinNames_y, indx_next)
   
   indx_last = indx_next
   do k=1,p%NumBlades
      call PackLoadMesh_Names(y%BladeLoad(k), 'Blade '//trim(num2lstr(k)), InitOut%LinNames_y, indx_next)
   end do
   ! InitOut%RotFrame_y(indx_last:indx_next-1) = .true. ! The mesh fields are in the global frame, so are not in the rotating frame

   do i=1,p%NumOuts + p%BldNd_TotNumOuts
      InitOut%LinNames_y(i+indx_next-1) = trim(InitOut%WriteOutputHdr(i))//', '//trim(InitOut%WriteOutputUnt(i))  !trim(p%OutParam(i)%Name)//', '//p%OutParam(i)%Units
   end do    
   

      ! check for all the WriteOutput values that are functions of blade number:
   allocate( AllOut(0:MaxOutPts), STAT=ErrStat2 ) ! allocate starting at zero to account for invalid output channels
   if (ErrStat2 /=0 ) then
      call SetErrStat(ErrID_Info, 'error allocating temporary space for AllOut',ErrStat,ErrMsg,RoutineName)
      return;
   end if
   
   AllOut = .false.
   do k=1,3
      AllOut( BAzimuth(k)) = .true.
      AllOut( BPitch  (k)) = .true.

      !   AllOut( BAeroFx( k)) = .true.
      !   AllOut( BAeroFy( k)) = .true.
      !   AllOut( BAeroFz( k)) = .true.
      !   AllOut( BAeroMx( k)) = .true.
      !   AllOut( BAeroMy( k)) = .true.
      !   AllOut( BAeroMz( k)) = .true.

      do j=1,9
         AllOut(BNVUndx(j,k)) = .true.
         AllOut(BNVUndy(j,k)) = .true.
         AllOut(BNVUndz(j,k)) = .true.
         AllOut(BNVDisx(j,k)) = .true.
         AllOut(BNVDisy(j,k)) = .true.
         AllOut(BNVDisz(j,k)) = .true.
         AllOut(BNSTVx (j,k)) = .true.
         AllOut(BNSTVy (j,k)) = .true.
         AllOut(BNSTVz (j,k)) = .true.
         AllOut(BNVRel (j,k)) = .true.
         AllOut(BNDynP (j,k)) = .true.
         AllOut(BNRe   (j,k)) = .true.
         AllOut(BNM    (j,k)) = .true.   
         AllOut(BNVIndx(j,k)) = .true.   
         AllOut(BNVIndy(j,k)) = .true. 
         AllOut(BNAxInd(j,k)) = .true.         
         AllOut(BNTnInd(j,k)) = .true.
         AllOut(BNAlpha(j,k)) = .true.
         AllOut(BNTheta(j,k)) = .true.
         AllOut(BNPhi  (j,k)) = .true.   
         AllOut(BNCurve(j,k)) = .true.
         AllOut(BNCl   (j,k)) = .true.
         AllOut(BNCd   (j,k)) = .true.
         AllOut(BNCm   (j,k)) = .true.
         AllOut(BNCx   (j,k)) = .true.
         AllOut(BNCy   (j,k)) = .true.
         AllOut(BNCn   (j,k)) = .true.
         AllOut(BNCt   (j,k)) = .true.
         AllOut(BNFl   (j,k)) = .true.
         AllOut(BNFd   (j,k)) = .true.
         AllOut(BNMm   (j,k)) = .true.
         AllOut(BNFx   (j,k)) = .true.
         AllOut(BNFy   (j,k)) = .true.
         AllOut(BNFn   (j,k)) = .true.
         AllOut(BNFt   (j,k)) = .true.
         AllOut(BNClrnc(j,k)) = .true.
      end do
   end do
   
   
   do i=1,p%NumOuts
      InitOut%RotFrame_y(i+indx_next-1) = AllOut( p%OutParam(i)%Indx )      
   end do    
   
   do i=1,p%BldNd_TotNumOuts
      InitOut%RotFrame_y(i+p%NumOuts+indx_next-1) = .true.
      !AbsCant, AbsToe, AbsTwist should probably be set to .false.
   end do
      
   
   deallocate(AllOut)
          
END SUBROUTINE Init_Jacobian_y
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE Init_Jacobian_u( InputFileData, p, u, InitOut, ErrStat, ErrMsg)

   TYPE(RotInputFile)                , INTENT(IN   ) :: InputFileData         !< input file data (for default blade perturbation)
   TYPE(RotParameterType)            , INTENT(INOUT) :: p                     !< parameters
   TYPE(RotInputType)                , INTENT(IN   ) :: u                     !< inputs
   TYPE(RotInitOutputType)           , INTENT(INOUT) :: InitOut               !< Initialization output data (for Jacobian row/column names)
   
   INTEGER(IntKi)                    , INTENT(  OUT) :: ErrStat               !< Error status of the operation
   CHARACTER(*)                      , INTENT(  OUT) :: ErrMsg                !< Error message if ErrStat /= ErrID_None
   
      ! local variables:
   INTEGER(IntKi)                :: i, j, k, index, index_last, nu, i_meshField
   REAL(ReKi)                    :: perturb, perturb_t, perturb_b(MaxBl)
   LOGICAL                       :: FieldMask(FIELDMASK_SIZE)
   CHARACTER(1), PARAMETER       :: UVW(3) = (/'U','V','W'/)
   INTEGER(IntKi)                                    :: ErrStat2
   CHARACTER(ErrMsgLen)                              :: ErrMsg2
   CHARACTER(*), PARAMETER                           :: RoutineName = 'Init_Jacobian_u'
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   
      ! determine how many inputs there are in the Jacobians
   nu = u%TowerMotion%NNodes * 9            & ! 3 Translation Displacements + 3 orientations + 3 Translation velocities at each node
      + u%hubMotion%NNodes   * 9            & ! 3 Translation Displacements + 3 orientations + 3 Rotation velocities at each node
      + size( u%InflowOnBlade)              &
      + size( u%InflowOnTower)              & !note that we are not passing the inflow on nacelle or hub here
      + size( u%UserProp)

   do i=1,p%NumBlades
      nu = nu + u%BladeMotion(i)%NNodes * 15 & ! 3 Translation Displacements + 3 orientations + 3 Translation velocities + 3 Rotation velocities + 3 TranslationAcc at each node
          + u%BladeRootMotion(i)%NNodes * 3   ! 3 orientations at each node
   end do      
      
   ! all other inputs ignored

      
   !............................                     
   ! fill matrix to store index to help us figure out what the ith value of the u vector really means
   ! (see aerodyn::perturb_u ... these MUST match )
   ! column 1 indicates module's mesh and field
   ! column 2 indicates the first index (x-y-z component) of the field
   ! column 3 is the node
   !............................                     
   
   call allocAry( p%Jac_u_indx, nu, 3, 'p%Jac_u_indx', ErrStat2, ErrMsg2)      
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   if (ErrStat >= AbortErrLev) return                     
            
   !...............
   ! AD input mappings stored in p%Jac_u_indx:   
   !...............            
   index = 1
   !Module/Mesh/Field: u%TowerMotion%TranslationDisp  = 1;
   !Module/Mesh/Field: u%TowerMotion%Orientation      = 2;
   !Module/Mesh/Field: u%TowerMotion%TranslationVel   = 3;
   do i_meshField = 1,3
      do i=1,u%TowerMotion%NNodes
         do j=1,3
            p%Jac_u_indx(index,1) =  i_meshField
            p%Jac_u_indx(index,2) =  j !component index:  j
            p%Jac_u_indx(index,3) =  i !Node:   i
            index = index + 1
         end do !j      
      end do !i
   end do
   
   !Module/Mesh/Field: u%HubMotion%TranslationDisp = 4;
   !Module/Mesh/Field: u%HubMotion%Orientation     = 5;
   !Module/Mesh/Field: u%HubMotion%RotationVel     = 6;
   do i_meshField = 4,6
      do i=1,u%HubMotion%NNodes
         do j=1,3
            p%Jac_u_indx(index,1) =  i_meshField
            p%Jac_u_indx(index,2) =  j !component index:  j
            p%Jac_u_indx(index,3) =  i !Node:   i
            index = index + 1
         end do !j      
      end do !i
   end do
   
   !bjj: if MaxBl (max blades) changes, we need to modify this
   !Module/Mesh/Field: u%BladeRootMotion(1)%Orientation = 7;
   !Module/Mesh/Field: u%BladeRootMotion(2)%Orientation = 8;
   !Module/Mesh/Field: u%BladeRootMotion(3)%Orientation = 9;   
   do k=1,p%NumBlades         
      do i_meshField = 6,6
         do i=1,u%BladeRootMotion(k)%NNodes
            do j=1,3
               p%Jac_u_indx(index,1) =  i_meshField + k
               p%Jac_u_indx(index,2) =  j !component index:  j
               p%Jac_u_indx(index,3) =  i !Node:   i
               index = index + 1
            end do !j      
         end do !i
            
      end do !i_meshField                            
   end do !k  
      
   !bjj: if MaxBl (max blades) changes, we need to modify this
   !Module/Mesh/Field: u%BladeMotion(1)%TranslationDisp = 10;
   !Module/Mesh/Field: u%BladeMotion(1)%Orientation     = 11;
   !Module/Mesh/Field: u%BladeMotion(1)%TranslationVel  = 12;
   !Module/Mesh/Field: u%BladeMotion(1)%RotationVel     = 13;
   !Module/Mesh/Field: u%BladeMotion(1)%TranslationAcc  = 14;

   !Module/Mesh/Field: u%BladeMotion(2)%TranslationDisp = 15;
   !Module/Mesh/Field: u%BladeMotion(2)%Orientation     = 16;
   !Module/Mesh/Field: u%BladeMotion(2)%TranslationVel  = 17;
   !Module/Mesh/Field: u%BladeMotion(2)%RotationVel     = 18;
   !Module/Mesh/Field: u%BladeMotion(2)%TranslationAcc  = 19;
   
   !Module/Mesh/Field: u%BladeMotion(3)%TranslationDisp = 20;
   !Module/Mesh/Field: u%BladeMotion(3)%Orientation     = 21;
   !Module/Mesh/Field: u%BladeMotion(3)%TranslationVel  = 22;
   !Module/Mesh/Field: u%BladeMotion(3)%RotationVel     = 23;
   !Module/Mesh/Field: u%BladeMotion(3)%TranslationAcc  = 24;
   do k=1,p%NumBlades
      do i_meshField = 1,5
         do i=1,u%BladeMotion(k)%NNodes
            do j=1,3
               p%Jac_u_indx(index,1) =  9 + i_meshField + (k-1)*5
               p%Jac_u_indx(index,2) =  j !component index:  j
               p%Jac_u_indx(index,3) =  i !Node:   i
               index = index + 1
            end do !j      
         end do !i
            
      end do !i_meshField                            
   end do !k
   
   !Module/Mesh/Field: u%InflowOnBlade(:,:,1) = 25;
   !Module/Mesh/Field: u%InflowOnBlade(:,:,2) = 26;
   !Module/Mesh/Field: u%InflowOnBlade(:,:,3) = 27;
   do k=1,size(u%InflowOnBlade,3)    ! p%NumBlades
      do i=1,size(u%InflowOnBlade,2) ! numNodes
         do j=1,3
            p%Jac_u_indx(index,1) =  24 + k
            p%Jac_u_indx(index,2) =  j !component index:  j
            p%Jac_u_indx(index,3) =  i !Node:   i
            index = index + 1
         end do !j      
      end do !i
   end do !k
   
   !Module/Mesh/Field: u%InflowOnTower(:,:) = 28;
   do i=1,size(u%InflowOnTower,2) ! numNodes
      do j=1,3
         p%Jac_u_indx(index,1) =  28
         p%Jac_u_indx(index,2) =  j !component index:  j
         p%Jac_u_indx(index,3) =  i !Node:   i
         index = index + 1
      end do !j      
   end do !i
   
   !Module/Mesh/Field: u%UserProp(:,:) = 29,30,31;
   
   do k=1,size(u%UserProp,2) ! p%NumBlades         
      do i=1,size(u%UserProp,1) ! numNodes
            p%Jac_u_indx(index,1) =  28 + k
            p%Jac_u_indx(index,2) =  1 !component index:  this is a scalar, so 1, but is never used
            p%Jac_u_indx(index,3) =  i !Node:   i
            index = index + 1     
      end do !i
   end do !k
      !......................................
      ! default perturbations, p%du:
      !......................................
   call allocAry( p%du, 31, 'p%du', ErrStat2, ErrMsg2) ! 31 = number of unique values in p%Jac_u_indx(:,1)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

   perturb = 2*D2R
   
   do k=1,p%NumBlades
      perturb_b(k) = 0.2_ReKi*D2R * InputFileData%BladeProps(k)%BlSpn( InputFileData%BladeProps(k)%NumBlNds )
   end do

   if ( u%TowerMotion%NNodes > 0) then
      perturb_t = 0.2_ReKi*D2R * u%TowerMotion%Position( 3, u%TowerMotion%NNodes )
   else
      perturb_t = 0.0_ReKi
   end if   
   
   p%du(1) = perturb_t                    ! u%TowerMotion%TranslationDisp  = 1
   p%du(2) = perturb                      ! u%TowerMotion%Orientation      = 2
   p%du(3) = perturb_t                    ! u%TowerMotion%TranslationVel   = 3
   p%du(4) = perturb_b(1)                 ! u%HubMotion%TranslationDisp    = 4
   p%du(5) = perturb                      ! u%HubMotion%Orientation        = 5
   p%du(6) = perturb                      ! u%HubMotion%RotationVel        = 6
   do i_meshField = 7,9   
      p%du(i_meshField) = perturb         ! u%BladeRootMotion(k)%Orientation = 6+k, for k in [1, 3]
   end do
   do k=1,p%NumBlades         
      p%du(10 + (k-1)*5) = perturb_b(k)   ! u%BladeMotion(k)%TranslationDisp = 10 + (k-1)*5
      p%du(11 + (k-1)*5) = perturb        ! u%BladeMotion(k)%Orientation     = 11 + (k-1)*5
      p%du(12 + (k-1)*5) = perturb_b(k)   ! u%BladeMotion(k)%TranslationVel  = 12 + (k-1)*5
      p%du(13 + (k-1)*5) = perturb        ! u%BladeMotion(k)%RotationVel     = 13 + (k-1)*5
      p%du(14 + (k-1)*5) = perturb_b(k)   ! u%BladeMotion(k)%TranslationAcc  = 14 + (k-1)*5 !bjj: is the correct????
   end do
   do k=1,p%NumBlades
      p%du(24 + k) = perturb_b(k)         ! u%InflowOnBlade(:,:,k) = 24 + k
   end do      
   p%du(28) = perturb_t                   ! u%InflowOnTower(:,:) = 28
   do k=1,p%NumBlades 
      p%du(28+k) = perturb                ! u%UserProp(:,:) = 29,30,31
   end do      
      !.....................
      ! get names of linearized inputs
      !.....................
   call AllocAry(InitOut%LinNames_u, nu, 'LinNames_u', ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   call AllocAry(InitOut%RotFrame_u, nu, 'RotFrame_u', ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   call AllocAry(InitOut%IsLoad_u, nu, 'IsLoad_u', ErrStat2, ErrMsg2)
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
      if (ErrStat >= AbortErrLev) return

   InitOut%IsLoad_u   = .false. ! None of AeroDyn's inputs are loads
   InitOut%RotFrame_u = .false.
   do k=0,p%NumBlades*p%NumBlNds-1
      InitOut%RotFrame_u(nu - k ) = .true.   ! UserProp(:,:)
   end do  
   index = 1
   FieldMask = .false.
   FieldMask(MASKID_TRANSLATIONDISP) = .true.
   FieldMask(MASKID_Orientation) = .true.
   FieldMask(MASKID_TRANSLATIONVel) = .true.
   call PackMotionMesh_Names(u%TowerMotion, 'Tower', InitOut%LinNames_u, index, FieldMask=FieldMask)
   
   FieldMask(MASKID_TRANSLATIONVel) = .false.
   FieldMask(MASKID_RotationVel) = .true.
   call PackMotionMesh_Names(u%HubMotion, 'Hub', InitOut%LinNames_u, index, FieldMask=FieldMask)

   index_last = index
   FieldMask = .false.
   FieldMask(MASKID_Orientation) = .true.
   do k = 1,p%NumBlades
      call PackMotionMesh_Names(u%BladeRootMotion(k), 'Blade root '//trim(num2lstr(k)), InitOut%LinNames_u, index, FieldMask=FieldMask)
   end do
   
   FieldMask(MASKID_TRANSLATIONDISP) = .true.
   FieldMask(MASKID_TRANSLATIONVel)  = .true.
   FieldMask(MASKID_RotationVel) = .true.
   FieldMask(MASKID_TRANSLATIONAcc)  = .true.
   do k=1,p%NumBlades
      call PackMotionMesh_Names(u%BladeMotion(k), 'Blade '//trim(num2lstr(k)), InitOut%LinNames_u, index, FieldMask=FieldMask)
   end do
   
   do k=1,p%NumBlades
      do i=1,p%NumBlNds
         do j=1,3
            InitOut%LinNames_u(index) = UVW(j)//'-component inflow on blade '//trim(num2lstr(k))//', node '//trim(num2lstr(i))//', m/s'
            index = index + 1
         end do
      end do
   end do
   !InitOut%RotFrame_u(index_last:index-1) = .true. ! values on the mesh (and from IfW) are in global coordinates, thus not in the rotating frame

   do i=1,p%NumTwrNds
      do j=1,3
         InitOut%LinNames_u(index) = UVW(j)//'-component inflow on tower node '//trim(num2lstr(i))//', m/s'
         index = index + 1
      end do
   end do

   do k=1,p%NumBlades
      do i=1,p%NumBlNds
         InitOut%LinNames_u(index) = 'User property on blade '//trim(num2lstr(k))//', node '//trim(num2lstr(i))//', -'
         index = index + 1
      end do
   end do

   END SUBROUTINE Init_Jacobian_u
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE Init_Jacobian_x( p, InitOut, ErrStat, ErrMsg)

   TYPE(RotParameterType)            , INTENT(INOUT) :: p                     !< parameters
   TYPE(RotInitOutputType)           , INTENT(INOUT) :: InitOut               !< Output for initialization routine
   
   INTEGER(IntKi)                    , INTENT(  OUT) :: ErrStat               !< Error status of the operation
   CHARACTER(*)                      , INTENT(  OUT) :: ErrMsg                !< Error message if ErrStat /= ErrID_None
   
   INTEGER(IntKi)                                    :: ErrStat2
   CHARACTER(ErrMsgLen)                              :: ErrMsg2
   CHARACTER(*), PARAMETER                           :: RoutineName = 'Init_Jacobian_x'
   
      ! local variables:
   INTEGER(IntKi)                :: i, j, k
   INTEGER(IntKi)                :: nx
   INTEGER(IntKi)                :: nx1
   CHARACTER(25)                 :: NodeTxt
   
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   
   nx = p%BEMT%DBEMT%lin_nx + p%BEMT%UA%lin_nx
   
      ! allocate space for the row/column names and for perturbation sizes
   ! always allocate this in case it is size zero ... (we use size(p%dx) for many calculations)
   CALL AllocAry(p%dx,                 nx, 'p%dx',         ErrStat2, ErrMsg2); call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   if (nx==0) return
   
   CALL AllocAry(InitOut%LinNames_x,   nx, 'LinNames_x',   ErrStat2, ErrMsg2); CALL SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   CALL AllocAry(InitOut%RotFrame_x,   nx, 'RotFrame_x',   ErrStat2, ErrMsg2); CALL SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   CALL AllocAry(InitOut%DerivOrder_x, nx, 'DerivOrder_x', ErrStat2, ErrMsg2); CALL SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)
   if (ErrStat >= AbortErrLev) return
   
      ! All DBEMT continuous states are order = 2; UA states are order 1
   
   ! set default perturbation sizes: p%dx
   p%dx = 2.0_R8Ki * D2R_D 
   
      ! set linearization output names:
   nx1 = p%BEMT%DBEMT%lin_nx/2
   if (nx1>0) then
      InitOut%DerivOrder_x(1:p%BEMT%DBEMT%lin_nx) = 2
      InitOut%RotFrame_x(  1:p%BEMT%DBEMT%lin_nx) = .true.
   
      k = 1
      do j=1,p%NumBlades ! size(x%BEMT%DBEMT%element,2)
         do i=1,p%NumBlNds ! size(x%BEMT%DBEMT%element,1)
            NodeTxt = 'blade '//trim(num2lstr(j))//', node '//trim(num2lstr(i))
            InitOut%LinNames_x(k) = 'vind (axial) at '//trim(NodeTxt)//', m/s'
            k = k + 1
            
            InitOut%LinNames_x(k) = 'vind (tangential) at '//trim(NodeTxt)//', m/s'
            k = k + 1
         end do
      end do
   
      do i=1,nx1
         InitOut%LinNames_x(i+nx1) = 'First time derivative of '//trim(InitOut%LinNames_x(i))//'/s'
         InitOut%RotFrame_x(i+nx1) = InitOut%RotFrame_x(i)
      end do
   end if
   
   if (p%BEMT%UA%lin_nx>0) then
      InitOut%DerivOrder_x(1+p%BEMT%DBEMT%lin_nx:nx) = 1
      InitOut%RotFrame_x(  1+p%BEMT%DBEMT%lin_nx:nx) = .true.
   
      k = 1 + p%BEMT%DBEMT%lin_nx
      do j=1,p%NumBlades ! size(x%BEMT%DBEMT%element,2)
         do i=1,p%NumBlNds ! size(x%BEMT%DBEMT%element,1)
            NodeTxt = 'blade '//trim(num2lstr(j))//', node '//trim(num2lstr(i))
            
            InitOut%LinNames_x(k) = 'x1 '//trim(NodeTxt)//', rad'
            k = k + 1

            InitOut%LinNames_x(k) = 'x2 '//trim(NodeTxt)//', rad'
            k = k + 1
            
            InitOut%LinNames_x(k) = 'x3 '//trim(NodeTxt)//', -'
            k = k + 1
            
            InitOut%LinNames_x(k) = 'x4 '//trim(NodeTxt)//', -'
            p%dx(k) = 0.001 ! x4 is a number between 0 and 1, so we need this to be small
            k = k + 1
         end do
      end do
      
   end if
   
END SUBROUTINE Init_Jacobian_x
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine initializes the array that maps rows/columns of the Jacobian to specific mesh fields.
!! Do not change the order of this packing without changing corresponding parts of AD linearization !
SUBROUTINE Init_Jacobian( InputFileData, p, p_AD, u, y, m, InitOut, ErrStat, ErrMsg)

   type(RotInputFile)                , intent(in   ) :: InputFileData         !< input file data (for default blade perturbation)
   TYPE(RotParameterType)            , INTENT(INOUT) :: p                     !< parameters
   TYPE(AD_ParameterType)            , INTENT(INOUT) :: p_AD                  !< parameters
   TYPE(RotInputType)                , INTENT(IN   ) :: u                     !< inputs
   TYPE(RotOutputType)               , INTENT(IN   ) :: y                     !< outputs
   TYPE(RotMiscVarType)              , INTENT(IN   ) :: m                     !< miscellaneous variable
   TYPE(RotInitOutputType)           , INTENT(INOUT) :: InitOut               !< Initialization output data (for Jacobian row/column names)
   
   INTEGER(IntKi)                    , INTENT(  OUT) :: ErrStat               !< Error status of the operation
   CHARACTER(*)                      , INTENT(  OUT) :: ErrMsg                !< Error message if ErrStat /= ErrID_None
   
   INTEGER(IntKi)                                    :: ErrStat2
   CHARACTER(ErrMsgLen)                              :: ErrMsg2
   CHARACTER(*), PARAMETER                           :: RoutineName = 'Init_Jacobian'
   
   
   ErrStat = ErrID_None
   ErrMsg  = ""
  
!FIXME: add logic to check that p%NumBlades is not greater than MaxBl.  Cannot linearize if that is true. 
   call Init_Jacobian_y( p, y, InitOut, ErrStat, ErrMsg)
   
      ! these matrices will be needed for linearization with frozen wake feature
   if (p%FrozenWake) then
      call AllocAry(m%BEMT%AxInd_op,p%NumBlNds,p%numBlades,'m%BEMT%AxInd_op', ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
      call AllocAry(m%BEMT%TnInd_op,p%NumBlNds,p%numBlades,'m%BEMT%TnInd_op', ErrStat2,ErrMsg2); call SetErrStat(ErrStat2,ErrMsg2,ErrStat,ErrMsg,RoutineName)
   end if
   
   call Init_Jacobian_u( InputFileData, p, u, InitOut, ErrStat2, ErrMsg2); call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

   call Init_Jacobian_x( p, InitOut, ErrStat2, ErrMsg2); call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName)

END SUBROUTINE Init_Jacobian
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine perturbs the nth element of the u array (and mesh/field it corresponds to)
!! Do not change this without making sure subroutine aerodyn::init_jacobian is consistant with this routine!
SUBROUTINE Perturb_u( p, n, perturb_sign, u, du )

   TYPE(RotParameterType)              , INTENT(IN   ) :: p                      !< parameters
   INTEGER( IntKi )                    , INTENT(IN   ) :: n                      !< number of array element to use 
   INTEGER( IntKi )                    , INTENT(IN   ) :: perturb_sign           !< +1 or -1 (value to multiply perturbation by; positive or negative difference)
   TYPE(RotInputType)                  , INTENT(INOUT) :: u                      !< perturbed AD inputs
   REAL( R8Ki )                        , INTENT(  OUT) :: du                     !< amount that specific input was perturbed
   

   ! local variables
   INTEGER                                             :: fieldIndx
   INTEGER                                             :: node
      
   fieldIndx = p%Jac_u_indx(n,2) 
   node      = p%Jac_u_indx(n,3) 
   
   du = p%du(  p%Jac_u_indx(n,1) )
   
      ! determine which mesh we're trying to perturb and perturb the input:
   SELECT CASE( p%Jac_u_indx(n,1) )
      
   CASE ( 1) !Module/Mesh/Field: u%TowerMotion%TranslationDisp = 1;
      u%TowerMotion%TranslationDisp( fieldIndx,node) = u%TowerMotion%TranslationDisp( fieldIndx,node) + du * perturb_sign
   CASE ( 2) !Module/Mesh/Field: u%TowerMotion%Orientation = 2;
      CALL PerturbOrientationMatrix( u%TowerMotion%Orientation(:,:,node), du * perturb_sign, fieldIndx )
   CASE ( 3) !Module/Mesh/Field: u%TowerMotion%TranslationVel = 3;
      u%TowerMotion%TranslationVel( fieldIndx,node ) = u%TowerMotion%TranslationVel( fieldIndx,node) + du * perturb_sign
      
   CASE ( 4) !Module/Mesh/Field: u%HubMotion%TranslationDisp = 4;
      u%HubMotion%TranslationDisp(fieldIndx,node) = u%HubMotion%TranslationDisp(fieldIndx,node) + du * perturb_sign
   CASE ( 5) !Module/Mesh/Field: u%HubMotion%Orientation = 5;
      CALL PerturbOrientationMatrix( u%HubMotion%Orientation(:,:,node), du * perturb_sign, fieldIndx )
   CASE ( 6) !Module/Mesh/Field: u%HubMotion%RotationVel = 6;
      u%HubMotion%RotationVel(fieldIndx,node) = u%HubMotion%RotationVel(fieldIndx,node) + du * perturb_sign
   
   CASE ( 7) !Module/Mesh/Field: u%BladeRootMotion(1)%Orientation = 7;
      CALL PerturbOrientationMatrix( u%BladeRootMotion(1)%Orientation(:,:,node), du * perturb_sign, fieldIndx )

   CASE ( 8) !Module/Mesh/Field: u%BladeRootMotion(2)%Orientation = 8;
      CALL PerturbOrientationMatrix( u%BladeRootMotion(2)%Orientation(:,:,node), du * perturb_sign, fieldIndx )
      
   CASE ( 9) !Module/Mesh/Field: u%BladeRootMotion(3)%Orientation = 9;
      CALL PerturbOrientationMatrix( u%BladeRootMotion(3)%Orientation(:,:,node), du * perturb_sign, fieldIndx )
      
   CASE (10) !Module/Mesh/Field: u%BladeMotion(1)%TranslationDisp = 10;
      u%BladeMotion(1)%TranslationDisp(fieldIndx,node) = u%BladeMotion(1)%TranslationDisp(fieldIndx,node) + du * perturb_sign
   CASE (11) !Module/Mesh/Field: u%BladeMotion(1)%Orientation = 11;
      CALL PerturbOrientationMatrix( u%BladeMotion(1)%Orientation(:,:,node), du * perturb_sign, fieldIndx )
   CASE (12) !Module/Mesh/Field: u%BladeMotion(1)%TranslationVel = 12;
      u%BladeMotion(1)%TranslationVel(fieldIndx,node) = u%BladeMotion(1)%TranslationVel(fieldIndx,node) + du * perturb_sign
   CASE (13) !Module/Mesh/Field: u%BladeMotion(1)%RotationVel = 13;
      u%BladeMotion(1)%RotationVel(fieldIndx,node) = u%BladeMotion(1)%RotationVel(fieldIndx,node) + du * perturb_sign
   CASE (14) !Module/Mesh/Field: u%BladeMotion(1)%TranslationAcc = 14;
      u%BladeMotion(1)%TranslationAcc(fieldIndx,node) = u%BladeMotion(1)%TranslationAcc(fieldIndx,node) + du * perturb_sign
      
   CASE (15) !Module/Mesh/Field: u%BladeMotion(2)%TranslationDisp = 15;
      u%BladeMotion(2)%TranslationDisp( fieldIndx,node) = u%BladeMotion(2)%TranslationDisp( fieldIndx,node) + du * perturb_sign
   CASE (16) !Module/Mesh/Field: u%BladeMotion(2)%Orientation = 16;
      CALL PerturbOrientationMatrix( u%BladeMotion(2)%Orientation(:,:,node), du * perturb_sign, fieldIndx )
   CASE (17) !Module/Mesh/Field: u%BladeMotion(2)%TranslationVel = 17;
      u%BladeMotion(2)%TranslationVel(fieldIndx,node) = u%BladeMotion(2)%TranslationVel(fieldIndx,node) + du * perturb_sign
   CASE (18) !Module/Mesh/Field: u%BladeMotion(2)%RotationVel = 18;
      u%BladeMotion(2)%RotationVel(fieldIndx,node) = u%BladeMotion(2)%RotationVel(fieldIndx,node) + du * perturb_sign
   CASE (19) !Module/Mesh/Field: u%BladeMotion(2)%TranslationAcc = 19;
      u%BladeMotion(2)%TranslationAcc(fieldIndx,node) = u%BladeMotion(2)%TranslationAcc(fieldIndx,node) + du * perturb_sign
      
   CASE (20) !Module/Mesh/Field: u%BladeMotion(3)%TranslationDisp = 20;
      u%BladeMotion(3)%TranslationDisp( fieldIndx,node) = u%BladeMotion(3)%TranslationDisp( fieldIndx,node) + du * perturb_sign
   CASE (21) !Module/Mesh/Field: u%BladeMotion(3)%Orientation = 21;
      CALL PerturbOrientationMatrix( u%BladeMotion(3)%Orientation(:,:,node), du * perturb_sign, fieldIndx )
   CASE (22) !Module/Mesh/Field: u%BladeMotion(3)%TranslationVel = 22;
      u%BladeMotion(3)%TranslationVel(fieldIndx,node) = u%BladeMotion(3)%TranslationVel(fieldIndx,node) + du * perturb_sign
   CASE (23) !Module/Mesh/Field: u%BladeMotion(3)%RotationVel = 23;
      u%BladeMotion(3)%RotationVel(fieldIndx,node) = u%BladeMotion(3)%RotationVel(fieldIndx,node) + du * perturb_sign
   CASE (24) !Module/Mesh/Field: u%BladeMotion(3)%TranslationAcc = 24;
      u%BladeMotion(3)%TranslationAcc(fieldIndx,node) = u%BladeMotion(3)%TranslationAcc(fieldIndx,node) + du * perturb_sign

   CASE (25) !Module/Mesh/Field: u%InflowOnBlade(:,:,1) = 25;
      u%InflowOnBlade(fieldIndx,node,1) = u%InflowOnBlade(fieldIndx,node,1) + du * perturb_sign
   CASE (26) !Module/Mesh/Field: u%InflowOnBlade(:,:,2) = 26;
      u%InflowOnBlade(fieldIndx,node,2) = u%InflowOnBlade(fieldIndx,node,2) + du * perturb_sign
   CASE (27) !Module/Mesh/Field: u%InflowOnBlade(:,:,3) = 27;
      u%InflowOnBlade(fieldIndx,node,3) = u%InflowOnBlade(fieldIndx,node,3) + du * perturb_sign
      
   CASE (28) !Module/Mesh/Field: u%InflowOnTower(:,:)   = 28;
      u%InflowOnTower(fieldIndx,node) = u%InflowOnTower(fieldIndx,node) + du * perturb_sign
   CASE (29) !Module/Mesh/Field: u%UserProp(:,1)   = 29; 
      u%UserProp(node,1) = u%UserProp(node,1) + du * perturb_sign
   CASE (30) !Module/Mesh/Field: u%UserProp(:,2)   = 30; 
      u%UserProp(node,2) = u%UserProp(node,2) + du * perturb_sign
   CASE (31) !Module/Mesh/Field: u%UserProp(:,3)   = 31; 
      u%UserProp(node,3) = u%UserProp(node,3) + du * perturb_sign
   END SELECT
      
END SUBROUTINE Perturb_u
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine perturbs the nth element of the u array (and mesh/field it corresponds to)
!! Do not change this without making sure subroutine aerodyn::init_jacobian is consistant with this routine!
SUBROUTINE Perturb_x( p, n, perturb_sign, x, dx )

   TYPE(RotParameterType)              , INTENT(IN   ) :: p                      !< parameters
   INTEGER( IntKi )                    , INTENT(IN   ) :: n                      !< number of array element to use 
   INTEGER( IntKi )                    , INTENT(IN   ) :: perturb_sign           !< +1 or -1 (value to multiply perturbation by; positive or negative difference)
   TYPE(RotContinuousStateType)        , INTENT(INOUT) :: x                      !< perturbed AD continuous states
   REAL( R8Ki )                        , INTENT(  OUT) :: dx                     !< amount that specific input was perturbed
   

   ! local variables
   INTEGER(IntKi)    :: Blade             ! loop over blade nodes
   INTEGER(IntKi)    :: BladeNode         ! loop over blades
   INTEGER(IntKi)    :: StateIndex        ! loop over blades


   dx   = p%dx( n )
   
   if (n <= p%BEMT%DBEMT%lin_nx) then

      if (n <= p%BEMT%DBEMT%lin_nx/2) then ! x_p%BEMT%DBEMT%element(i,j)%vind, else x_p%BEMT%DBEMT%element(i,j)%vind_dot
         call GetStateIndices( n, size(x%BEMT%DBEMT%element,2), size(x%BEMT%DBEMT%element,1), size(x%BEMT%DBEMT%element(1,1)%vind), Blade, BladeNode, StateIndex )
         x%BEMT%DBEMT%element(BladeNode,Blade)%vind(StateIndex) = x%BEMT%DBEMT%element(BladeNode,Blade)%vind(StateIndex) + dx * perturb_sign
      else
         call GetStateIndices( n - p%BEMT%DBEMT%lin_nx/2, size(x%BEMT%DBEMT%element,2), size(x%BEMT%DBEMT%element,1), size(x%BEMT%DBEMT%element(1,1)%vind_dot), Blade, BladeNode, StateIndex )
         x%BEMT%DBEMT%element(BladeNode,Blade)%vind_dot(StateIndex) = x%BEMT%DBEMT%element(BladeNode,Blade)%vind_dot(StateIndex) + dx * perturb_sign
      endif
   
   else
      !call GetStateIndices( n - p%BEMT%DBEMT%lin_nx, size(x%BEMT%UA%element,2), size(x%BEMT%UA%element,1), size(x%BEMT%UA%element(1,1)%x), Blade, BladeNode, StateIndex )
      call GetStateIndices( n - p%BEMT%DBEMT%lin_nx, size(x%BEMT%UA%element,2), size(x%BEMT%UA%element,1), 4, Blade, BladeNode, StateIndex )
      x%BEMT%UA%element(BladeNode,Blade)%x(StateIndex) = x%BEMT%UA%element(BladeNode,Blade)%x(StateIndex) + dx * perturb_sign
   
   end if

contains
   subroutine GetStateIndices( Indx, NumberOfBlades, NumberOfElementsPerBlade, NumberOfStatesPerElement, Blade, BladeNode, StateIndex )
   
      integer(IntKi), intent(in   ) :: Indx
      integer(IntKi), intent(in   ) :: NumberOfBlades             !< how many blades (size of array)
      integer(IntKi), intent(in   ) :: NumberOfElementsPerBlade   !< how many nodes per blades (size of array)
      integer(IntKi), intent(in   ) :: NumberOfStatesPerElement   !< how many states at each blade element
      
      integer(IntKi), intent(  out) :: Blade
      integer(IntKi), intent(  out) :: BladeNode
      integer(IntKi), intent(  out) :: StateIndex
      
      integer(IntKi)                :: CheckNum
      

      StateIndex = mod(Indx-1, NumberOfStatesPerElement ) + 1    ! returns a number in [1,NumberOfStatesPerElement]
      
      CheckNum = (Indx - StateIndex)/NumberOfStatesPerElement
      BladeNode = mod(CheckNum, NumberOfElementsPerBlade ) + 1   ! returns a number in [1,NumberOfElementsPerBlade]
      
      Blade = (CheckNum - BladeNode + 1)/NumberOfElementsPerBlade + 1

   end subroutine GetStateIndices
END SUBROUTINE Perturb_x
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine uses values of two output types to compute an array of differences.
!! Do not change this packing without making sure subroutine aerodyn::init_jacobian is consistant with this routine!
SUBROUTINE Compute_dY(p, y_p, y_m, delta_p, delta_m, dY)
   
   TYPE(RotParameterType)            , INTENT(IN   ) :: p         !< parameters
   TYPE(RotOutputType)               , INTENT(IN   ) :: y_p       !< AD outputs at \f$ u + \Delta_p u \f$ or \f$ x + \Delta_p x \f$ (p=plus)
   TYPE(RotOutputType)               , INTENT(IN   ) :: y_m       !< AD outputs at \f$ u - \Delta_m u \f$ or \f$ x - \Delta_m x \f$ (m=minus)   
   REAL(R8Ki)                        , INTENT(IN   ) :: delta_p   !< difference in inputs or states \f$ delta_p = \Delta_p u \f$ or \f$ delta_p = \Delta_p x \f$
   REAL(R8Ki)                        , INTENT(IN   ) :: delta_m   !< difference in inputs or states \f$ delta_m = \Delta_m u \f$ or \f$ delta_m = \Delta_m x \f$
   REAL(R8Ki)                        , INTENT(INOUT) :: dY(:)     !< column of dYdu or dYdx: \f$ \frac{\partial Y}{\partial u_i} = \frac{y_p - y_m}{2 \, \Delta u}\f$ or \f$ \frac{\partial Y}{\partial x_i} = \frac{y_p - y_m}{2 \, \Delta x}\f$
   
      ! local variables:
   INTEGER(IntKi)    :: k              ! loop over blades
   INTEGER(IntKi)    :: indx_first     ! index indicating next value of dY to be filled 

   
   
   indx_first = 1
   call PackLoadMesh_dY(y_p%TowerLoad, y_m%TowerLoad, dY, indx_first)
   
   do k=1,p%NumBlades
      call PackLoadMesh_dY(y_p%BladeLoad(k), y_m%BladeLoad(k), dY, indx_first)
   end do
   
   
   do k=1,p%NumOuts + p%BldNd_TotNumOuts
      dY(k+indx_first-1) = y_p%WriteOutput(k) - y_m%WriteOutput(k)
   end do   
   
   
   dY = dY / (delta_p + delta_m)
   
END SUBROUTINE Compute_dY
!----------------------------------------------------------------------------------------------------------------------------------
!> This routine uses values of two continuous state types to compute an array of differences.
!! Do not change this packing without making sure subroutine aerodyn::init_jacobian is consistant with this routine!
SUBROUTINE Compute_dX(p, x_p, x_m, delta_p, delta_m, dX)
   
   TYPE(RotParameterType)            , INTENT(IN   ) :: p         !< parameters
   TYPE(RotContinuousStateType)      , INTENT(IN   ) :: x_p       !< AD continuous states at \f$ u + \Delta_p u \f$ or \f$ x + \Delta_p x \f$ (p=plus)
   TYPE(RotContinuousStateType)      , INTENT(IN   ) :: x_m       !< AD continuous states at \f$ u - \Delta_m u \f$ or \f$ x - \Delta_m x \f$ (m=minus)
   REAL(R8Ki)                        , INTENT(IN   ) :: delta_p   !< difference in inputs or states \f$ delta_p = \Delta_p u \f$ or \f$ delta_p = \Delta_p x \f$
   REAL(R8Ki)                        , INTENT(IN   ) :: delta_m   !< difference in inputs or states \f$ delta_m = \Delta_m u \f$ or \f$ delta_m = \Delta_m x \f$
   REAL(R8Ki)                        , INTENT(INOUT) :: dX(:)     !< column of dXdu or dXdx: \f$ \frac{\partial Y}{\partial u_i} = \frac{y_p - y_m}{2 \, \Delta u}\f$ or \f$ \frac{\partial Y}{\partial x_i} = \frac{y_p - y_m}{2 \, \Delta x}\f$
   
      ! local variables:
   INTEGER(IntKi)    :: i              ! loop over blade nodes
   INTEGER(IntKi)    :: j              ! loop over blades
   INTEGER(IntKi)    :: indx_first     ! index indicating next value of dY to be filled 

   
   indx_first = 1
   
   if (p%BEMT%DBEMT%lin_nx > 0) then
   
      do j=1,size(x_p%BEMT%DBEMT%element,2) ! number of blades
         do i=1,size(x_p%BEMT%DBEMT%element,1) ! number of nodes per blade
            dX(indx_first:indx_first+1) = x_p%BEMT%DBEMT%element(i,j)%vind - x_m%BEMT%DBEMT%element(i,j)%vind
            indx_first = indx_first + size(x_p%BEMT%DBEMT%element(i,j)%vind) !+= 2
         end do
      end do
   
      do j=1,size(x_p%BEMT%DBEMT%element,2) ! number of blades
         do i=1,size(x_p%BEMT%DBEMT%element,1) ! number of nodes per blade
            dX(indx_first:indx_first+1) = x_p%BEMT%DBEMT%element(i,j)%vind_dot - x_m%BEMT%DBEMT%element(i,j)%vind_dot
            indx_first = indx_first + size(x_p%BEMT%DBEMT%element(i,j)%vind_dot) !+=2
         end do
      end do
      
   end if
   
   if (p%BEMT%UA%lin_nx>0) then
   
      do j=1,size(x_p%BEMT%UA%element,2) ! number of blades
         do i=1,size(x_p%BEMT%UA%element,1) ! number of nodes per blade
            dX(indx_first:indx_first+3) = x_p%BEMT%UA%element(i,j)%x(1:4) - x_m%BEMT%UA%element(i,j)%x(1:4)
            indx_first = indx_first + 4 ! = index_first += 4
         end do
      end do

   end if

   dX = dX / (delta_p + delta_m)
   
END SUBROUTINE Compute_dX
!----------------------------------------------------------------------------------------------------------------------------------
END MODULE AeroDyn
