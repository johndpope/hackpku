//
//  Model.m
//  Face
//
//  Created by 曾兆阳 on 16/4/9.
//  Copyright © 2016年 ZengZhaoyang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Model.h"
#import <iostream>
#import <string>
#import <vector>
#import <utility>
#import <algorithm>
#import <queue>
#import <map>
#import <set>
#import <memory>
#import <math.h>
#import <time.h>

#import "boost/algorithm/string.hpp"
#import "google/protobuf/text_format.h"

#define CPU_ONLY
#define USE_EIGEN

#import <caffe/blob.hpp>
#import <caffe/common.hpp>
#import <caffe/net.hpp>
#import <caffe/proto/caffe.pb.h>
#import <caffe/util/io.hpp>
#import <caffe/vision_layers.hpp>

#import <Eigen/Dense>

using caffe::Blob;
using caffe::Caffe;
using caffe::Datum;
using caffe::Net;
using caffe::Layer;
using namespace std;

struct pr {
    float score;
    int id;
    pr() {
        id = -1;
        score = -1;
    }
    pr(float _score, int _id) {
        score = _score;
        id = _id;
    }
};

bool operator< (const pr &a, const pr &b) {
    return a.score > b.score;
}

class CaffeModel {
public:
    CaffeModel() {
        init();
    }
    ~CaffeModel() {
        delete []label_names;
        delete []result_labels;
        delete []result_score;
    }
    
    void predict(string &img_path) {
        const float* feature = extractFeature(img_path);
        predictLabelByFeature(feature);
    }
    
    const string* getResult() {
        return result_labels;
    }
    
    const float* getScore() {
        return result_score;
    }
    
private:
    
    void init() {
        initFilePath();
        initNameList(272);
        initNet();
    }
    
    void initFilePath() {
        template_path = [[NSBundle mainBundle] pathForResource:@"your_prototxt" ofType:@"prototxt"];
        
        NSString *_model_path = [[NSBundle mainBundle] pathForResource:@"your_model" ofType:@"caffemodel"];
        model_path = [_model_path cStringUsingEncoding:NSUTF8StringEncoding];
        
        data_name = "your_data_layer";
        blob_name = "your_prob_layer";
        
        NSArray *root_paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        
        index_path = [[root_paths objectAtIndex:0] stringByAppendingPathComponent:@"your_index"];
        
        _prototxt_path = [[root_paths objectAtIndex:0] stringByAppendingPathComponent:@"real.prototxt"];
        prototxt_path = [_prototxt_path cStringUsingEncoding:NSUTF8StringEncoding];
        
        num_mini_batches = 1;
    }
    
    void initNameList(int _label_num) {
        label_num = _label_num;
        NSString *namelist_path = [[NSBundle mainBundle] pathForResource:@"your_namelist" ofType:@"txt"];
        FILE *file = fopen([namelist_path cStringUsingEncoding:NSUTF8StringEncoding], "r");
        char label[1000];
        label_names = new string[label_num];
        for (int i = 0; i < label_num; i++) {
            fgets(label, 1000, file);
            int len = strlen(label);
            label[len-1] = '\0';
            label_names[i] = label;
        }
        result_labels = new string[5];
        result_score = new float[5];
    }
    
    void initNet() {
        Caffe::set_mode(Caffe::CPU);
        Caffe::set_phase(Caffe::TEST);
        NSString *init_img_path = [[NSBundle mainBundle] pathForResource:@"init" ofType:@"jpg"];
        init_img_path = [init_img_path stringByAppendingString:@" 0"];
        [init_img_path writeToFile:index_path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        NSString *prototxt_content = [NSString stringWithContentsOfFile:template_path encoding:NSUTF8StringEncoding error:nil];
        prototxt_content = [NSString stringWithFormat:prototxt_content,index_path];
        [prototxt_content writeToFile:_prototxt_path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        net = shared_ptr<Net<float> >(new Net<float>(prototxt_path));
        net->CopyTrainedLayersFrom(model_path);
        
        printf("init success\n");
    }
    
    const float* extractFeature(string &img_path) {
        const shared_ptr<Layer<float> > _layer = net->layer_by_name(data_name);
        caffe::ImageDataLayer<float> *layer = (caffe::ImageDataLayer<float> *)_layer.get();
        
        layer->setImgPath(img_path, 0);
        layer->JoinPrefetchThread();
        layer->CreatePrefetchThread();
        
        vector<Blob<float>*> input_vec;
        net->Forward(input_vec);
        const shared_ptr<Blob<float> > blob = net->blob_by_name(blob_name);
        return blob->cpu_data();
    }
    
    void predictLabelByFeature(const float* feature) {
        priority_queue<pr> q;
        int cnt = 0;
        for (int i = 0; i < label_num; i++) {
            q.push(pr(feature[i], i));
            if (cnt < 5) {
                cnt++;
            }
            else {
                q.pop();
            }
        }

        for (int i = 4; i >= 0; i--) {
            result_labels[i] = label_names[q.top().id];
            result_score[i] = q.top().score;
            q.pop();
        }

    }
    
    int label_num;
    string *label_names;
    NSString *template_path;
    string model_path;
    NSString *index_path;
    NSString *_prototxt_path;
    string prototxt_path;
    string data_name;
    string blob_name;
    int num_mini_batches;
    shared_ptr<Net<float> > net;
    string *result_labels;
    float *result_score;
    
};


@interface Model() {
    CaffeModel model;
}

@end

@implementation Model

- (NSMutableArray*)getImageLabels: (NSString*)imageName {
    
    string imgName = string([imageName cStringUsingEncoding:NSUTF8StringEncoding]);
    
    model.predict(imgName);
    const string* labels = model.getResult();
    const float* scores = model.getScore();
    
    NSMutableArray *res = [[NSMutableArray alloc] init];
    for (int i = 0; i < 5; i++) {
        NSString *real_label = [NSString stringWithCString:labels[i].c_str() encoding:NSUTF8StringEncoding];
        NSNumber *real_score = [NSNumber numberWithFloat:scores[i]];
        NSDictionary *tempDic = [[NSDictionary alloc] initWithObjectsAndKeys:real_label, @"label", real_score, @"score", nil];
        [res addObject:tempDic];
    }
    
    return res;
}

@end