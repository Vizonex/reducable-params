# cython: freethreading_compatible = True

from types import GenericAlias

cimport cython
from cpython.dict cimport (
    PyDict_Contains,
    PyDict_Copy,
    PyDict_GetItem,
    PyDict_GetItemWithError,
    PyDict_SetItem
)
from cpython.object cimport PyObject, PyObject_Call
from cpython.set cimport PySet_Contains
from cpython.tuple cimport (
    PyTuple_GET_ITEM,
    PyTuple_GET_SIZE,
    PyTuple_New
)

from .abc import Reducable
from .utils import varnames


cdef extern from "Python.h":
    object PyTuple_GetItemObj "PyTuple_GET_ITEM"(object p, Py_ssize_t pos) noexcept

    void PyTuple_SetItemPtr "PyTuple_SET_ITEM"(object  p, Py_ssize_t pos, PyObject* val) noexcept
    int PyDict_SetItemPtr "PyDict_SetItem"(object p, object key, PyObject* val) except -1
    Py_ssize_t PyDict_GET_SIZE(dict p)

# This should be enough callables for any decently sized application.
DEF REDUCE_FREELIST_SIZE = 250 

@cython.freelist(REDUCE_FREELIST_SIZE)
cdef class reduce:
    cdef:
        public object __wrapped__
        dict _defaults
        str _name
        Py_ssize_t _nargs, _nparams
        tuple _optional
        tuple _params
        frozenset _param_set
        tuple _required

    __class_getitem__ = classmethod(GenericAlias)

    def __init__(
        self,
        object func
    ) -> None:
        cdef tuple required
        cdef dict optional
        # The only bottlekneck is here when ititalizing althought this part is not planned to be benchmarked.
        required, optional = varnames(func)

        if name := getattr(func, "__name__", None):
            self._name = f"{name}()"
        else:
            self._name = "function"

        self.__wrapped__ = func
        self._defaults = optional
        self._nargs = len(required)
        self._optional = tuple(optional.keys())
        self._params = required + self._optional
        self._param_set = frozenset(self._params)
        self._nparams = len(self._params)
        self._required = required

    def install(self, *args, **kwargs):
        r"""Simillar to `inspect.BoundArguments` but a little bit faster,
        it is based off CPython's getargs.c's algorythms, this will also attempt to
        install defaults if any are needed. However this does not allow arbitrary
        arguments to be passed through. Instead, this should primarly be
        used for writing callback utilities that require a parent function's signature.

        :raises TypeError: if argument parsing fails or has a argument that overlaps in either args or kwargs.
        """
        # Mimics checks from vgetargskeywordsfast_impl in getargs.c
        cdef Py_ssize_t nargs = PyTuple_GET_SIZE(args)
        cdef Py_ssize_t ntotal = nargs +  PyDict_GET_SIZE(kwargs)
        cdef Py_ssize_t n
        cdef frozenset params = self._param_set
        cdef object k, v
        cdef dict output

        if ntotal < self._nargs:
            raise TypeError(f"Not enough params in {self._name}")

        elif ntotal > self._nparams:
            raise TypeError(
                "%.200s takes at most %d %sargument%s (%i given)" % (
                    self._name,
                    self._nparams,
                    "keyword" if not self._nargs else "",
                    "" if self._nparams == 1 else "s",
                    ntotal
                )
            )

        # Begin parsing while checking for overlapping arguments and copy off all the defaults.

        output = PyDict_Copy(self._defaults)
        for n in range(nargs):
            k = self._params[n]
            if PyDict_Contains(kwargs, k):
                # arg present in tuple and dict
                raise TypeError(
                    "argument for %.200s given by name ('%s') and position (%d)" % (
                    self._name, k, n + 1
                    )
                )
            PyDict_SetItemPtr(output, k, PyTuple_GET_ITEM(args, n))


        # replace rest of the defaults with keyword arguments
        for k, v in kwargs.items():
            # force up a keyerror if object is not present in the
            # actual defaults
            if not PySet_Contains(params, k):
                raise KeyError(k)
            PyDict_SetItem(output, k, v)

        return output

    @cython.nonecheck(False)
    def __call__(self, dict kwds):
        """Calls reduction wrapper and calls function
        while ignoring any unwanted arguments. This is useful
        when chaining together callbacks with different function
        formations."""

        cdef dict kwargs = PyDict_Copy(self._defaults)
        cdef tuple args = PyTuple_New(self._nargs)
        cdef PyObject* v
        cdef Py_ssize_t k

        for k, key in enumerate(self._required):
            v = PyDict_GetItemWithError(kwds, key)
            PyTuple_SetItemPtr(args, k, v)

        for key in self._params[self._nargs:]:
            v = PyDict_GetItem(kwds, key)
            if v != NULL:
                PyDict_SetItemPtr(kwargs, key, v)

        return PyObject_Call(self.__wrapped__, args, kwargs)


Reducable.register(reduce)

