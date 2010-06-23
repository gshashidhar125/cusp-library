/*
 *  Copyright 2008-2009 NVIDIA Corporation
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#include <cusp/detail/convert.h>

#include <thrust/sort.h>
#include <thrust/is_sorted.h>
#include <thrust/iterator/zip_iterator.h>

namespace cusp
{

//////////////////
// Constructors //
//////////////////
        
// construct empty matrix
template <typename IndexType, typename ValueType, class MemorySpace>
coo_matrix<IndexType,ValueType,MemorySpace>
    ::coo_matrix()
        : detail::matrix_base<IndexType,ValueType,MemorySpace>() {}

// construct matrix with given shape and number of entries
template <typename IndexType, typename ValueType, class MemorySpace>
coo_matrix<IndexType,ValueType,MemorySpace>
    ::coo_matrix(IndexType num_rows, IndexType num_cols, IndexType num_entries)
        : detail::matrix_base<IndexType,ValueType,MemorySpace>(num_rows, num_cols, num_entries),
          row_indices(num_entries), column_indices(num_entries), values(num_entries) {}

// construct from another coo_matrix
template <typename IndexType, typename ValueType, class MemorySpace>
template <typename IndexType2, typename ValueType2, typename MemorySpace2>
coo_matrix<IndexType,ValueType,MemorySpace>
    ::coo_matrix(const coo_matrix<IndexType2, ValueType2, MemorySpace2>& matrix)
        : detail::matrix_base<IndexType,ValueType,MemorySpace>(matrix.num_rows, matrix.num_cols, matrix.num_entries),
          row_indices(matrix.row_indices), column_indices(matrix.column_indices), values(matrix.values) {}
        
// construct from a different matrix format
template <typename IndexType, typename ValueType, class MemorySpace>
template <typename MatrixType>
coo_matrix<IndexType,ValueType,MemorySpace>
    ::coo_matrix(const MatrixType& matrix)
    {
        cusp::detail::convert(matrix, *this);
    }

//////////////////////
// Member Functions //
//////////////////////
        
// resize matrix shape and storage
template <typename IndexType, typename ValueType, class MemorySpace>
    void
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::resize(IndexType num_rows, IndexType num_cols, IndexType num_entries)
    {
        this->num_rows    = num_rows;
        this->num_cols    = num_cols;
        this->num_entries = num_entries;

        row_indices.resize(num_entries);
        column_indices.resize(num_entries);
        values.resize(num_entries);
    }

// swap matrix contents
template <typename IndexType, typename ValueType, class MemorySpace>
    void
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::swap(coo_matrix& matrix)
    {
        detail::matrix_base<IndexType,ValueType,MemorySpace>::swap(matrix);

        row_indices.swap(matrix.row_indices);
        column_indices.swap(matrix.column_indices);
        values.swap(matrix.values);
    }

// assignment from another coo_matrix
template <typename IndexType, typename ValueType, class MemorySpace>
template <typename IndexType2, typename ValueType2, typename MemorySpace2>
    coo_matrix<IndexType,ValueType,MemorySpace>&
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::operator=(const coo_matrix<IndexType2, ValueType2, MemorySpace2>& matrix)
    {
        // TODO use matrix_base::operator=
        this->num_rows       = matrix.num_rows;
        this->num_cols       = matrix.num_cols;
        this->num_entries    = matrix.num_entries;
        this->row_indices    = matrix.row_indices;
        this->column_indices = matrix.column_indices;
        this->values         = matrix.values;

        return *this;
    }

// assignment from another matrix format
template <typename IndexType, typename ValueType, class MemorySpace>
template <typename MatrixType>
    coo_matrix<IndexType,ValueType,MemorySpace>&
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::operator=(const MatrixType& matrix)
    {
        cusp::detail::convert(matrix, *this);
        
        return *this;
    }

// sort matrix elements by row index
template <typename IndexType, typename ValueType, class MemorySpace>
    void
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::sort_by_row(void)
    {
        thrust::sort_by_key(row_indices.begin(),
                            row_indices.end(),
                            thrust::make_zip_iterator(thrust::make_tuple(column_indices.begin(), values.begin())));
    }

// determine whether matrix elements are sorted by row index
template <typename IndexType, typename ValueType, class MemorySpace>
    bool
    coo_matrix<IndexType,ValueType,MemorySpace>
    ::is_sorted_by_row(void)
    {
        return thrust::is_sorted(row_indices.begin(), row_indices.end());
    }

} // end namespace cusp

