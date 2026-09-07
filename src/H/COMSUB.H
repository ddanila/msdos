/* Common utility subroutines. */

extern unsigned comgetarg (
	unsigned *,	   /* number of arguments		    */
	char **,	   /* pointer array of original arguments   */
	char **,	   /* pointer of argument unit character    */
			   /* storage				    */
	unsigned,	   /* depth of new argument pointer array   */
	char *, 	   /* broken down argument character buffer */
	unsigned,	   /* size of argument character buffer     */
	char *, 	   /* current defualt drive name	    */
	char *);	   /* switching character		    */
/*
 * print a message and get a response
 */
extern unsigned computmsg (
	char **,	   /* table of variables  to insert	  */
	unsigned,	   /* number of variables to insert	  */
	unsigned,	   /* message id			  */
	char *, 	   /* message file name 		  */
	unsigned,	   /* output device type		  */
	unsigned,	   /* response type			  */
	char *, 	   /* response data area		  */
	unsigned);	   /* size of response data area	  */
/*
 *  verify correct DOS version
 */
extern unsigned comcheckdosver();

/*
 *  return code conversion to message id
 */
extern unsigned rctomid(
	unsigned);	   /* return code to converted to msg id */

/*
 *  open drive in real mode
 */
extern unsigned far pascal REALOPEN(
	char far *,	   /* pointer to drive name */
	unsigned far *,    /* pointer to drive handle */
	unsigned);	   /* open mode */

/*****************************************/
/*					 */
/*	   DBCS common subroutine	 */
/*					 */
/*****************************************/
/*
 *   search the first substring occurrence in a string
 */
extern unsigned char
*com_substr(
   unsigned char *,	      /* source string */
   unsigned char *);	      /* target string */

/*
 *   search the last charater occurrence in a string
 */
extern unsigned char
*com_strrchr(
   unsigned char *,	      /* source string */
   unsigned char );	     /* target string */

/*
 *   compare two strings with regard to case
 */
extern int
com_strcmpi(
  unsigned char *,	      /* source string	       */
  unsigned char *);	      /* string to be compared */

/*
 *   convert a string to uppercase
 */
extern unsigned char
*com_strupr(
   unsigned char *);	      /* string to be converted */

/*
 *   convert a string to lowercase
 */
extern unsigned char
*com_strlwr(
   unsigned char *);	      /* string to be converted */

/*
 *   search the first occurrence of a character in a string
 */
extern char *com_strchr(
   unsigned char *,	      /* a source string */
   unsigned char );	      /* a character to be searched */

/*
 *   convert character to uppercase
 */
extern int com_toupper(
   unsigned char );	      /* character to be converted to uppercase */

/*
 *   convert character to lowercase
 */
extern int com_tolower(
   unsigned char );	      /* character to be converted to lowercase */

/*************************************
 *				     *
 *   external variable declaration   *
 *				     *
 *************************************/
extern unsigned cm_invalid_parm_pointer;  /* points to first detected	 */
					  /* invalid argument string	 */

extern char cm_flhandle_enable_sw;    /* enable filehandle input for	     */
				      /* computmsg routine		     */
				      /*				     */
				      /* if this switch is on (non-zero),    */
				      /* filehandle can be set in devicetype.*/

extern char cm_trace_cmd_flg;	      /* ignore drive validity check.	     */
				      /*   if it set to 1, COMGETARG does    */
				      /*   not check drive validity.	     */
