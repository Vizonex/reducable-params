#ifndef __REDUCE_PACKER_H__
#define __REDUCE_PACKER_H__

#include <Python.h>

#ifdef __cplusplus
extern "C" {
#endif

/* This was more or less an optimization & Not wanting cython 
to screw around or trigger segfaults with in the most critical sections 
The entire reduce module could be moved to C if problems persist.
*/

static PyObject* reduce_call(
    PyObject* kwds, 
    PyObject* r_wrapped,
    PyObject* r_defaults, 
    PyObject* r_required,
    PyObject* r_params,
    const Py_ssize_t n_required,
    const Py_ssize_t n_params
){
    PyObject* key, *v, *result;
    result = NULL;
    PyObject* kwargs = PyDict_Copy(r_defaults);
    if (kwargs == NULL) goto cleanup;
    PyObject* args = PyTuple_New(n_required);
    if (args == NULL) goto cleanup;
 
    for (Py_ssize_t i = 0; i < n_required; i++){
        key = PyTuple_GET_ITEM(r_required, i);
        v = PyDict_GetItemWithError(kwds, key);
        if (v == NULL)
            goto cleanup;
        PyTuple_SET_ITEM(args, i, v);
    }

    for (Py_ssize_t j = n_required; j < n_params; j++){
        key = PyTuple_GET_ITEM(r_params, j);
        v = PyDict_GetItem(kwds, key);
        if (v != NULL)
            PyDict_SetItem(kwargs, key, v);
    }

    result = PyObject_Call(r_wrapped, args, kwargs);
cleanup:
    Py_CLEAR(kwargs);
    Py_CLEAR(args);
    return result;
}




#ifdef __cplusplus
}
#endif 


#endif // __REDUCE_PACKER_H__