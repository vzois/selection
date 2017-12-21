#include <cub/cub.cuh>
#include "time/Time.h"
#include "tools/ArgParser.h"
#include "tools/File.h"
#include "time/Time.h"

#include "cuda/CudaHelper.h"

#include "selection/selection_test.h"
#include "selection/selection.h"

#define BLOCK_SIZE 512

template<class T>
void micro_bench(T *gdata, uint64_t *gres, uint64_t n, uint64_t d, uint64_t match_pred){

	//Start Processing
	dim3 grid(n/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	for(int i=0; i < 10; i++) select_and_for<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, d, match_pred);
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
	for(int i=0; i < 10; i++) select_and_8_for<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, match_pred);
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_for");
	for(int i=0; i < 10; i++) select_and_8_for_unroll<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, match_pred);
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_for_unroll");
	for(int i=0; i < 10; i++) select_and_8_register<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, match_pred);
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_register");
	for(int i=0; i < 10; i++) select_and_8_register_index<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, match_pred);
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_register_index");

}

template<class T>
void micro_bench2(T *gdata, uint64_t *gres, uint64_t n, uint64_t d, uint64_t match_pred, uint64_t iter, uint64_t and_){
	//Start Processing
	dim3 grid(n/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	if (and_ == 0){
//		std::cout << "items:" << d << std::endl;
		for(uint64_t i=0; i < iter; i++) select_and_for<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, d, match_pred);
		cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
	}else{
		for(uint64_t i=0; i < iter; i++) select_or_for_stop<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, d, match_pred);
		cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
	}

}

template<class T>
void micro_bench3(T *gdata, uint64_t *gres, uint64_t *gres_out, uint8_t *bvector, uint64_t *dnum,void *d_temp_storage,size_t temp_storage_bytes, uint64_t n, uint64_t d, uint64_t match_pred, uint64_t iter, uint64_t and_){
	//Start Processing
	dim3 grid(n/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	if (and_ == 0){
		//for(uint64_t i=0; i < iter; i++) select_and_for_stop<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,gres, n, d, match_pred);
		for(uint64_t i=0; i < iter; i++){
			select_and_for_gather<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,bvector, n, d, match_pred);
			cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for_gather 2");
			cub::DevicePartition::Flagged(d_temp_storage,temp_storage_bytes,gres,bvector,gres_out,dnum, n);
			cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
		}
	}else{
		for(uint64_t i=0; i < iter; i++){
			select_or_for_gather<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,bvector, n, d, match_pred);
			cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for_gather 2");
			cub::DevicePartition::Flagged(d_temp_storage,temp_storage_bytes,gres,bvector,gres_out,dnum, n);
			cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
		}
	}
}

template<class T>
void micro_bench4(T *gdata, uint64_t *gres, uint64_t *gres_out, uint8_t *bvector, uint64_t *dnum,void *d_temp_storage,size_t temp_storage_bytes, uint64_t n, uint64_t d, uint64_t match_pred, uint64_t iter, uint64_t and_){
	//Start Processing
	dim3 grid(n/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	for(uint64_t i=0; i < iter; i++){
		select_and_for_tpch<uint64_t,BLOCK_SIZE><<<grid,block>>>(gdata,bvector, n);
		cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for_gather 2");
		cub::DevicePartition::Flagged(d_temp_storage,temp_storage_bytes,gres,bvector,gres_out,dnum, n);
		cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing select_generic_for");
	}
}

int fetch(uint64_t &d,uint64_t &mx, float &s, FILE *f){
	int dd,mxx;
	float ss;
	//fscanf(f,"%i",&dd);
	int r = fscanf(f,"%i,%f,%i",&dd,&ss,&mxx);
	d=dd;
	mx =mxx;
	s =ss;
	//std::cout << "<<" <<dd << "," << mxx << "," << ss << std::endl;
	return r;
}

int main(int argc, char **argv){
	ArgParser ap;
	ap.parseArgs(argc,argv);

	if(!ap.exists("-f")){
		std::cout << "Missing file input!!! (-f)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-t")){
		std::cout << "Missing query type!!! (-t)" << std::endl;
		exit(1);
	}


	uint64_t mx=0,d=0;
	float s=0;
	uint64_t and_ = ap.getInt("-t");

	//Initialize load wrapper and pointers
	File<uint64_t> f(ap.getString("-f"),true);
	uint64_t *data = NULL;
	uint64_t *gdata = NULL;
	uint8_t *bvector = NULL;
	uint64_t *gres = NULL;
	uint64_t *gres_out = NULL;
	uint64_t *dnum = NULL;

	void *d_temp_storage = NULL;
	size_t temp_storage_bytes;

	cutil::safeMallocHost<uint64_t,uint64_t>(&(data),sizeof(uint64_t)*f.items()*f.rows(),"data alloc");//data from file
	cutil::safeMalloc<uint64_t,uint64_t>(&(gdata),sizeof(uint64_t)*f.items()*f.rows(),"gdata alloc");//data in GPU
	cutil::safeMalloc<uint64_t,uint64_t>(&(gres),sizeof(uint64_t)*f.rows(),"gres alloc");//row ids
	cutil::safeMalloc<uint8_t,uint64_t>(&(bvector),sizeof(uint8_t)*f.rows(),"bvector alloc");//boolean vector for evaluated rows
	cutil::safeMalloc<uint64_t,uint64_t>(&(gres_out),sizeof(uint64_t)*f.rows(),"gres_out alloc");//qualifying rows
	cutil::safeMalloc<uint64_t,uint64_t>(&(dnum),sizeof(uint64_t),"dnum alloc");//number of rows qualified

	cub::DevicePartition::Flagged(d_temp_storage,temp_storage_bytes,gres,bvector,gres_out,dnum, f.rows());//call to allocate temp_storage
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing ids partition");//synchronize
	cutil::safeMalloc<void,uint64_t>(&(d_temp_storage),temp_storage_bytes,"tmp_storage alloc");//alloc temp storage

	dim3 grid(f.rows()/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	init_ids<BLOCK_SIZE><<<grid,block>>>(gres,f.rows());
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing init ids");//synchronize

	//Load data
	f.set_transpose(true);
	f.load(data);
	//f.sample();

	//Transfer to GPU
	cutil::safeCopyToDevice<uint64_t,uint64_t>(gdata,data,sizeof(uint64_t)*f.items()*f.rows(), " copy from data to gdata ");

	FILE *fa;
	fa = fopen("args.out", "r");
	uint64_t iter = 10;

	if(and_ < 2){
		while (fetch(d,mx,s,fa) >0){
			Time<msecs> t;
			t.start();
			micro_bench3<uint64_t>(gdata,gres,gres_out,bvector,dnum,d_temp_storage,temp_storage_bytes,f.rows(),d,mx,iter,and_);
			std::cout << s << "," << d << "," << t.lap()/iter <<std::endl;
			if(s == 1) std::cout << std::endl;
		}
	}else{
		Time<msecs> t;
		t.start();
		micro_bench4<uint64_t>(gdata,gres,gres_out,bvector,dnum,d_temp_storage,temp_storage_bytes,f.rows(),d,mx,iter,and_);
		std::cout << s << "," << d << "," << t.lap()/iter <<std::endl;
	}

	fclose(fa);

	cudaFreeHost(data);
	cudaFree(gdata);
	cudaFree(gres);
	cudaFree(bvector);
	cudaFree(gres_out);
	cudaFree(d_temp_storage);
	cudaFree(dnum);

	return 0;
}

int main2(int argc, char **argv){
	ArgParser ap;
	ap.parseArgs(argc,argv);

	if(!ap.exists("-f")){
		std::cout << "Missing file input!!! (-f)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-mx")){
		std::cout << "Missing maximum value!!! (-mx)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-s")){
		std::cout << "Missing selectivity!!! (-s)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-d")){
		std::cout << "Missing predicate size!!! (-d)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-t")){
		std::cout << "Missing query type!!! (-t)" << std::endl;
		exit(1);
	}

	uint64_t mx = ap.getInt("-mx");
	float s = ap.getFloat("-s");
	uint64_t d = ap.getInt("-d");
	uint64_t and_ = ap.getInt("-t");

	//Initialize load wrapper and pointers
	File<uint64_t> f(ap.getString("-f"),true);
	uint64_t *data = NULL;
	uint64_t *res = NULL;
	uint64_t *gdata = NULL;
	uint64_t *gres = NULL;

	cutil::safeMallocHost<uint64_t,uint64_t>(&(data),sizeof(uint64_t)*f.items()*f.rows(),"data alloc");
	cutil::safeMallocHost<uint64_t,uint64_t>(&(res),sizeof(uint64_t)*f.rows(),"res alloc");
	cutil::safeMalloc<uint64_t,uint64_t>(&(gdata),sizeof(uint64_t)*f.items()*f.rows(),"gdata alloc");
	cutil::safeMalloc<uint64_t,uint64_t>(&(gres),sizeof(uint64_t)*f.rows(),"gres alloc");

	//Load data
	f.set_transpose(true);
	f.load(data);
	//f.sample();

	//Transfer to GPU
	cutil::safeCopyToDevice<uint64_t,uint64_t>(gdata,data,sizeof(uint64_t)*f.items()*f.rows(), " copy from data to gdata ");

	uint64_t iter = 10;
	Time<msecs> t;
	t.start();
	micro_bench2(gdata,gres, f.rows(), d, mx, iter, and_);
	//std::cout << "<" << mx << "," << s << "," << d << "> : " << t.lap() <<std::endl;
	//std::cout << "selectivity: " << s << " pred: " << d << " time(ms): " << t.lap()/iter <<std::endl;
	std::cout << s << "," << d << "," << t.lap()/iter <<std::endl;

	//micro_bench2(gdata,gres, n, d, match_pred);

	cudaFreeHost(data);
	cudaFreeHost(res);
	cudaFree(gdata);
	cudaFree(gres);

	return 0;
}

int main3(int argc, char **argv){
	ArgParser ap;
	ap.parseArgs(argc,argv);

	if(!ap.exists("-f")){
		std::cout << "Missing file input!!! (-f)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-mx")){
		std::cout << "Missing maximum value!!! (-mx)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-s")){
		std::cout << "Missing selectivity!!! (-s)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-d")){
		std::cout << "Missing predicate size!!! (-d)" << std::endl;
		exit(1);
	}

	if(!ap.exists("-t")){
		std::cout << "Missing query type!!! (-t)" << std::endl;
		exit(1);
	}

	uint64_t mx = ap.getInt("-mx");
	float s = ap.getFloat("-s");
	uint64_t d = ap.getInt("-d");
	uint64_t and_ = ap.getInt("-t");

	//Initialize load wrapper and pointers
	File<uint64_t> f(ap.getString("-f"),true);
	uint64_t *data = NULL;
	uint64_t *gdata = NULL;
	uint8_t *bvector = NULL;
	uint64_t *gres = NULL;
	uint64_t *gres_out = NULL;
	uint64_t *dnum = NULL;

	void *d_temp_storage = NULL;
	size_t temp_storage_bytes;

	cutil::safeMallocHost<uint64_t,uint64_t>(&(data),sizeof(uint64_t)*f.items()*f.rows(),"data alloc");//data from file
	cutil::safeMalloc<uint64_t,uint64_t>(&(gdata),sizeof(uint64_t)*f.items()*f.rows(),"gdata alloc");//data in GPU
	cutil::safeMalloc<uint64_t,uint64_t>(&(gres),sizeof(uint64_t)*f.rows(),"gres alloc");//row ids
	cutil::safeMalloc<uint8_t,uint64_t>(&(bvector),sizeof(uint8_t)*f.rows(),"bvector alloc");//boolean vector for evaluated rows
	cutil::safeMalloc<uint64_t,uint64_t>(&(gres_out),sizeof(uint64_t)*f.rows(),"gres_out alloc");//qualifying rows
	cutil::safeMalloc<uint64_t,uint64_t>(&(dnum),sizeof(uint64_t),"dnum alloc");//number of rows qualified

	cub::DevicePartition::Flagged(d_temp_storage,temp_storage_bytes,gres,bvector,gres_out,dnum, f.rows());//call to allocate temp_storage
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing ids partition");//synchronize
	cutil::safeMalloc<void,uint64_t>(&(d_temp_storage),temp_storage_bytes,"tmp_storage alloc");//alloc temp storage

	dim3 grid(f.rows()/BLOCK_SIZE,1,1);
	dim3 block(BLOCK_SIZE,1,1);

	init_ids<BLOCK_SIZE><<<grid,block>>>(gres,f.rows());
	cutil::cudaCheckErr(cudaDeviceSynchronize(),"Error executing init ids");//synchronize

	//Load data
	f.set_transpose(true);
	f.load(data);
	//f.sample();

	//Transfer to GPU
	cutil::safeCopyToDevice<uint64_t,uint64_t>(gdata,data,sizeof(uint64_t)*f.items()*f.rows(), " copy from data to gdata ");

	uint64_t iter = 10;
	Time<msecs> t;
	t.start();
	micro_bench3<uint64_t>(gdata,gres,gres_out,bvector,dnum,d_temp_storage,temp_storage_bytes,f.rows(),d,mx,iter,and_);
	std::cout << s << "," << d << "," << t.lap()/iter <<std::endl;

//	t.start();
//	micro_bench2(gdata,gres, f.rows(), d, mx, iter, and_);
//	std::cout << s << "," << d << "," << t.lap()/iter <<std::endl;

	cudaFreeHost(data);
	cudaFree(gdata);
	cudaFree(gres);
	cudaFree(bvector);
	cudaFree(gres_out);
	cudaFree(d_temp_storage);
	cudaFree(dnum);

	return 0;
}
