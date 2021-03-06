#ifndef _DIFFUSION_MODEL_H_
#define _DIFFUSION_MODEL_H_

#include "Space.h"
#include "Grid.h"
#include "Array.h"

class DiffusionModel : public Griddable3D
{
protected:
    Grid<3> grid;
    
    std::vector<int> probabilisticRound (const Space<3>::Point &point, const int size = 3) const;
    
public:
    virtual ~DiffusionModel () {}
    
    virtual Space<3>::Vector sampleDirection (const Space<3>::Point &point, const Space<3>::Vector &referenceDirection) const
    {
        return Space<3>::zeroVector();
    }
    
    Grid<3> getGrid3D () const { return grid; }
};

class DiffusionTensorModel : public DiffusionModel
{
private:
    Array<float> *principalDirections;
    
public:
    DiffusionTensorModel ()
        : principalDirections(NULL) {}
    
    DiffusionTensorModel (const std::string &pdFile);
    
    ~DiffusionTensorModel ()
    {
        delete principalDirections;
    }
    
    Space<3>::Vector sampleDirection (const Space<3>::Point &point, const Space<3>::Vector &referenceDirection) const;
};

class BedpostModel : public DiffusionModel
{
private:
    std::vector<Array<float>*> avf, theta, phi;
    int nCompartments;
    int nSamples;
    float avfThreshold;
    
public:
    BedpostModel ()
        : nCompartments(0), nSamples(0) {}
    
    BedpostModel (const std::vector<std::string> &avfFiles, const std::vector<std::string> &thetaFiles, const std::vector<std::string> &phiFiles);
    
    ~BedpostModel ()
    {
        for (int i=0; i<nCompartments; i++)
        {
            delete avf[i];
            delete theta[i];
            delete phi[i];
        }
    }
    
    int getNCompartments () const { return nCompartments; }
    int getNSamples () const { return nSamples; }
    float getAvfThreshold () const { return avfThreshold; }
    
    void setAvfThreshold (const float avfThreshold) { this->avfThreshold = avfThreshold; }
    
    Space<3>::Vector sampleDirection (const Space<3>::Point &point, const Space<3>::Vector &referenceDirection) const;
};

#endif
