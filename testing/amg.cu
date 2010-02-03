#include <unittest/unittest.h>

#include <cusp/array2d.h>

// REMOVE THIS
#include <cusp/print.h>

// TAKE THESE
#include <cusp/multiply.h>

#include <thrust/count.h>
#include <thrust/iterator/permutation_iterator.h>
#include <thrust/transform.h>



template <typename IndexType>
struct filter_strong_connections
{
    template <typename Tuple>
    __host__ __device__
    IndexType operator()(const Tuple& t)
    {
        IndexType s_i = thrust::get<2>(t);
        IndexType s_j = thrust::get<3>(t);

        if (!s_i &&  s_j) return 1; // F->C connection
        if (!s_i && !s_j) return 0; // F->F connection

        IndexType i   = thrust::get<0>(t);
        IndexType j   = thrust::get<1>(t);
        
        if (s_i && i == j) return 1; // C->C connection (self connection)
        else return 0;
    }
};

template <typename IndexType, typename ValueType>
struct is_F_node : public thrust::unary_function<IndexType,ValueType>
{
    __host__ __device__
    ValueType operator()(const IndexType& i) const
    {
        return (i) ? ValueType(0) : ValueType(1);
    }
};

template <typename ValueType>
struct compute_weights
{
    template <typename Tuple>
    __host__ __device__
    ValueType operator()(const Tuple& t, const ValueType& v)
    {
        if (thrust::get<0>(t))  // C node w_ij = 0
            return 1;
        else                    // F node w_ij = |A_ij| / nu
            return ((v < 0) ? -v : v) / thrust::get<1>(t);
    }
};

template <typename IndexType, typename ValueType, typename SpaceOrAlloc,
          typename ArrayType>
void direct_interpolation(const cusp::coo_matrix<IndexType,ValueType,SpaceOrAlloc>& A,   // TODO make these const
                          const cusp::coo_matrix<IndexType,ValueType,SpaceOrAlloc>& C,   // TODO make these const
                          const ArrayType& cf_splitting,                                 // TODO make these const
                          cusp::coo_matrix<IndexType,ValueType,SpaceOrAlloc>& P)
{
    // dimensions of P
    const IndexType num_rows = A.num_rows;
    const IndexType num_cols = thrust::count(cf_splitting.begin(), cf_splitting.end(), 1);
  
    // mark the strong edges that are retained in P (either F->C or C->C self loops)
    cusp::array1d<IndexType,SpaceOrAlloc> stencil(C.num_entries);
    thrust::transform(thrust::make_zip_iterator(
                        thrust::make_tuple(C.row_indices.begin(),
                                           C.column_indices.begin(),
                                           thrust::make_permutation_iterator(cf_splitting.begin(), C.row_indices.begin()),
                                           thrust::make_permutation_iterator(cf_splitting.begin(), C.column_indices.begin()))),
                      thrust::make_zip_iterator(
                        thrust::make_tuple(C.row_indices.begin(),
                                           C.column_indices.begin(),
                                           thrust::make_permutation_iterator(cf_splitting.begin(), C.row_indices.begin()),
                                           thrust::make_permutation_iterator(cf_splitting.begin(), C.column_indices.begin()))) + C.num_entries,
                      stencil.begin(),
                      filter_strong_connections<IndexType>());

    // number of entries in P (number of F->C connections plus the number of C nodes)
    const IndexType num_entries = thrust::reduce(stencil.begin(), stencil.end());

    // sum the weights of the F nodes within each row
    cusp::array1d<ValueType,SpaceOrAlloc> nu(A.num_rows);
    {
        // nu = 1 / A * [F0F0F0]
        // scale C(i,j) by nu
        cusp::array1d<ValueType,SpaceOrAlloc> F_nodes(A.num_rows);  // 1.0 for F nodes, 0.0 for C nodes
        thrust::transform(cf_splitting.begin(), cf_splitting.end(), F_nodes.begin(), is_F_node<IndexType,ValueType>());
        cusp::multiply(A, F_nodes, nu);
    }
    
    // allocate storage for P
    {
        cusp::coo_matrix<IndexType,ValueType,SpaceOrAlloc> temp(num_rows, num_cols, num_entries);
        P.swap(temp);
    }

    // compute entries of P
    {
        // enumerate the C nodes
        cusp::array1d<ValueType,SpaceOrAlloc> coarse_index_map(A.num_rows);
        thrust::exclusive_scan(cf_splitting.begin(), cf_splitting.end(), coarse_index_map.begin());
       
        // TODO merge these copy_if() with a zip_iterator
        thrust::copy_if(C.row_indices.begin(), C.row_indices.end(),
                        stencil.begin(),
                        P.row_indices.begin(),
                        thrust::identity<IndexType>());
        thrust::copy_if(thrust::make_permutation_iterator(coarse_index_map.begin(), C.column_indices.begin()),
                        thrust::make_permutation_iterator(coarse_index_map.begin(), C.column_indices.end()),
                        stencil.begin(),
                        P.column_indices.begin(),
                        thrust::identity<IndexType>());
        thrust::copy_if(C.values.begin(), C.values.end(),
                        stencil.begin(),
                        P.values.begin(),
                        thrust::identity<IndexType>());

        thrust::transform(thrust::make_permutation_iterator(thrust::make_zip_iterator(thrust::make_tuple(cf_splitting.begin(), nu.begin())), P.row_indices.begin()), 
                          thrust::make_permutation_iterator(thrust::make_zip_iterator(thrust::make_tuple(cf_splitting.begin(), nu.begin())), P.row_indices.end()), 
                          P.values.begin(),
                          P.values.begin(),
                          compute_weights<ValueType>());
    }

//    std::cout << "P.num_rows    " << P.num_rows << std::endl;
//    std::cout << "P.num_cols    " << P.num_cols << std::endl;
//    std::cout << "P.num_entries " << P.num_entries << std::endl;
//    std::cout << "P.row_indices ";
//    cusp::print_matrix(P.row_indices);
//    std::cout << "P.column_indices ";
//    cusp::print_matrix(P.column_indices);
//    std::cout << "P.values ";
//    cusp::print_matrix(P.values);
}


template <class Space>
void TestDirectInterpolation(void)
{
    cusp::array2d<float, Space> A(5,5);
    A(0,0) =  2;  A(0,1) = -1;  A(0,2) =  0;  A(0,3) =  0;  A(0,4) =  0; 
    A(1,0) = -1;  A(1,1) =  2;  A(1,2) = -1;  A(1,3) =  0;  A(1,4) =  0;
    A(2,0) =  0;  A(2,1) = -1;  A(2,2) =  2;  A(2,3) = -1;  A(2,4) =  0;
    A(3,0) =  0;  A(3,1) =  0;  A(3,2) = -1;  A(3,3) =  2;  A(3,4) = -1;
    A(4,0) =  0;  A(4,1) =  0;  A(4,2) =  0;  A(4,3) = -1;  A(4,4) =  2;

    cusp::array1d<int, Space> cf_splitting(5);
    cf_splitting[0] = 1;
    cf_splitting[1] = 0;
    cf_splitting[2] = 1;
    cf_splitting[3] = 0;
    cf_splitting[4] = 1;

    // expected result 
    cusp::array2d<float, Space> E(5, 3);
    E(0,0) = 1.0;  E(0,1) = 0.0;  E(0,2) = 0.0;
    E(1,0) = 0.5;  E(1,1) = 0.5;  E(1,2) = 0.0;
    E(2,0) = 0.0;  E(2,1) = 1.0;  E(2,2) = 0.0;
    E(3,0) = 0.0;  E(3,1) = 0.5;  E(3,2) = 0.5;
    E(4,0) = 0.0;  E(4,1) = 0.0;  E(4,2) = 1.0;

    cusp::coo_matrix<int, float, Space> P_;
    cusp::coo_matrix<int,float,Space> A_(A);

    direct_interpolation(A_, A_, cf_splitting, P_);

    cusp::array2d<float, Space> P(P_);

    ASSERT_EQUAL_QUIET(P, E);
}
DECLARE_HOST_DEVICE_UNITTEST(TestDirectInterpolation);

