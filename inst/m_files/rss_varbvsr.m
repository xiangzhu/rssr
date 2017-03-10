function [lnZ, alpha, mu, s, info] = rss_varbvsr(betahat, se, SiRiS, sigb, logodds, options)
% USAGE: mean-field variational approximation of the RSS-BVSR model given the hyperparameters
% INPUT:
%       betahat: the effect size estimates under single-SNP model, p by 1
%       se: standard errors of betahat, p by 1
%       SiRiS: inv(S)*R*inv(S), double precision sparse matrix (ccs format), p by p
%       sigb: the prior SD of the regression coefficients (if included), scalar
%       logodds: the prior log-odds (i.e. log(prior PIP/(1-prior PIP))) of inclusion for each SNP, p by 1
%	option: user-specified behaviour of the algorithm, structure
% OUTPUT:
%	lnZ: scalar, the variational lower bound of the marginal log likelihood (up to some constant)
%	alpha: p by 1, variational estimates of the posterior inclusion probabilities 
%	mu: p by 1, posterior means of the additive effects (given snp included)
%	s: p by 1, posterior variances of the additive effects (given snp included)
%	info: structure with following fields 
%		- iter: integer, number of iterations
%       	- maxerr: the maximum relative difference between the parameters at the last two iterations
%		- sigb: scalar, the maximum likelihood estimate of sigma_beta
%		- loglik: iter by 1, the variational lower bound at each iteration

  % Convergence is reached when the maximum relative distance between
  % successive updates of the variational parameters is less than this
  % quantity.
  tolerance = 1e-4;
  
  % Get the number of variables (p).
  p = length(betahat);

  % SiRiS must be a sparse matrix.
  if ~issparse(SiRiS)
    SiRiS = sparse(double(SiRiS));
  end
  
  if ~exist('options', 'var')
    options = [];
  end

  % Set initial estimates of variational parameters.
  if isfield(options,'alpha')
    alpha = double(options.alpha(:));
  else
    alpha = rand(p,1);
    alpha = alpha / sum(alpha);
  end
  if isfield(options,'mu')
    mu = double(options.mu(:));
  else
    mu = randn(p,1);
  end
  if length(alpha) ~= p || length(mu) ~= p
    error('options.alpha and options.mu must be vectors of the same length');
  end

  % Determine whether to update the prior SD of the additive effects.
  if isfield(options,'update_sigb')
    update_sigb = options.update_sigb;
  else
    update_sigb = false;
  end

  % Determine whether to display the algorithm's progress.
  if isfield(options,'verbose')
    verbose = options.verbose;
  else
    verbose = true;
  end

  clear options;
  
  % Compute a few useful quantities for the main loop.
  SiRiSr = full(SiRiS * (alpha .* mu));
  q 	 = betahat ./ (se .^2);

  % Calculate the variance of the coefficients.
  se_square 	= se .* se;
  sigb_square 	= sigb * sigb;
  s 		= (se_square .* sigb_square) ./ (se_square + sigb_square);

  % Initialize the fields of the structure info.
  lnZ    = -Inf;
  iter   = 0;
  loglik = [];

  if verbose
    fprintf('       variational    max. incl max.       \n');
    fprintf('iter   lower bound  change vars E[b] sigma2\n');
  end

  % Repeat until convergence criterion is met.
  while true

    % Go to the next iteration.
    iter = iter + 1;
    
    % Save the current variational parameters and lower bound.
    alpha0  = alpha;
    mu0     = mu;
    lnZ0    = lnZ;
    params0 = [alpha; alpha .* mu];

    % Run a forward or backward pass of the coordinate ascent updates.
    if mod(iter,2)
      I = (1:p);
    else
      I = (p:-1:1);
    end
    [alpha, mu, SiRiSr] = rss_varbvsr_update(SiRiS, sigb, logodds, betahat, se, alpha, mu, SiRiSr, I);
    r = alpha .* mu; 

    % Compute the lower bound to the marginal log-likelihood.
    lnZ = q'*r - 0.5*r'*SiRiSr - 0.5*(1./se_square)'*betavar(alpha, mu, s);
    lnZ = lnZ + intgamma(logodds, alpha) + intklbeta_rssbvsr(alpha, mu, s, sigb_square);

    % Record the variational lower bound at each iteration.
    loglik = [loglik; lnZ]; %#ok<AGROW>

    % Compute the maximum pseudo-likelihood estimate of the prior SD of the
    % additive effects (sigma_beta), if requested. Note that we must also
    % recalculate the variational variance of the regression coefficients.
    if update_sigb
      sigb_square = dot(alpha, s+mu.^2) / sum(alpha);
      s 	  = (se_square .* sigb_square) ./ (se_square + sigb_square);
    end
    
    % Print the status of the algorithm and check the convergence criterion.
    % Convergence is reached when the maximum relative difference between
    % the parameters at two successive iterations is less than the specified
    % tolerance, or when the variational lower bound has decreased. I ignore
    % parameters that are very small.
    params = [alpha; r];
    I      = find(abs(params) > 1e-6);
    err    = relerr(params(I),params0(I));
    maxerr = max(err);

    if verbose
      status = sprintf('%4d %+13.6e %0.1e %4d %0.2f %5.2f',...
                       iter,lnZ,maxerr,round(sum(alpha)),max(abs(r)),sigb_square);
      fprintf(status);
      fprintf(repmat('\b',1,length(status)));
    end

    if lnZ < lnZ0
      if verbose
        fprintf('\n');
        fprintf('WARNING: the log variational lower bound decreased by %+0.2e\n',lnZ0-lnZ);
      end
      alpha = alpha0;
      mu    = mu0;
      lnZ   = lnZ0;
      sigb  = sqrt(sigb_square);
      break

    elseif maxerr < tolerance

      sigb = sqrt(sigb_square);
      if verbose
        fprintf('\n');
        fprintf('Convergence reached: maximum relative error %+0.2e\n',maxerr);
        fprintf('The log variational lower bound of the last step increased by %+0.2e\n',lnZ-lnZ0);
      end
      break

    end

  end

  % Save info as a structure array.
  info = struct('iter',iter,'maxerr',maxerr,'sigb',sigb,'loglik',loglik);
  
end
